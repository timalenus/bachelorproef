main() async {
  //config dataset and simulation
  var selectAmount = [108, 180, 180, 300, 360, 600]; //the amount of reservations we want in the dataset
  var numberOfCars = [3, 5, 3, 5, 3, 5]; 
  var numberOfWeeks = 4; //the amount of weeks we want in the dataset
  var numberOfRuns = 30; //the amount of simulations we want to do with these parameters

 for(var sim=0; sim<selectAmount.length; sim++) {

    var file = new File("${numberOfRuns}runs_${numberOfWeeks}weeks_${selectAmount[sim]}reservations_${numberOfCars[sim]}cars.csv");
    var sink = file.openWrite();
    sink.writeln("run, number of cars, amount of reservations, type, service level, time cars active, time not assigned");

    //await createNewReservationsFile();
    print("Reading reservations file");
    var reservationDetails = await readReservationDetailsFromFile("reservations");

    for(var i=1; i<=numberOfRuns; i++) {

      print("\n\n\nRUN${i}\n");

      var dataSet = await createDataset(selectAmount[sim], numberOfWeeks, reservationDetails);

      print("Total number of reservations ${dataSet.totalReservations}");
      print("Total duration of these reservations ${dataSet.totalDuration.toString()}");

      //easy assignment
      var solution1 = await doEasyAssignment(numberOfCars[sim], dataSet.clone());
      sink.writeln("${i}, ${numberOfCars[sim]},${selectAmount[sim]}, easy, ${solution1.serviceLevel},"
          "${solution1.totalCarUsageTime},${solution1.nonAssignedTime}");
      await solution1.exportSolutionToCsv("run${i}_${numberOfCars[sim]}_cars_${dataSet.totalReservations}_reservations", "easy");

      //csp assignment
      var solution2 = await doCspAssignment(numberOfCars[sim], dataSet.clone());
      sink.writeln("${i}, ${numberOfCars[sim]},${selectAmount[sim]}, csp, ${solution2.serviceLevel},"
          "${solution2.totalCarUsageTime},${solution2.nonAssignedTime}");
      await solution2.exportSolutionToCsv("run${i}_${numberOfCars[sim]}_cars_${dataSet.totalReservations}_reservations", "csp");
    }

    await sink.flush();
    await sink.close();
  }
}

Future<DataSet> createDataset(int selectAmount, int numberOfWeeks, Map<String, dynamic> reservationDetails) async {

  Map<int, Interval> selectedReservations = {};

  var totalReservations = 0;
  var skippedReservations = 0;
  do {
    var random = -1;
    //create randoms until we have one that has not been used yet
    do {
      random = new Random().nextInt(reservationDetails.length);
    } while(selectedReservations.containsKey(random));

    var reservation = reservationDetails.values.elementAt(random);

    //filter out the reservation if of no use to this simulation
    if (reservation["effectiveStartTime"]!=null&&
        reservation["effectiveEndTime"]!=null&&reservation["startStatus"]!=null&&
        reservation["endStatus"]!=null&&reservation["group"]=="cvba") {

      var effectiveStartTime = DateTime.parse(reservation["effectiveStartTime"]);
      var effectiveEndTime = DateTime.parse(reservation["effectiveEndTime"]);
      var duration = effectiveEndTime.difference(effectiveStartTime);

      if(duration < new Duration(days: 1) && duration > new Duration(minutes: 5) && effectiveStartTime.day==effectiveEndTime.day) {
        selectedReservations.putIfAbsent(random, () => new Interval(effectiveStartTime, effectiveEndTime));
        totalReservations++;
      }
      else {
        skippedReservations++;
      }
    }

  } while(totalReservations != selectAmount);
  /*print("Skipped ${skippedReservations} reservations because they were longer then 24hours or shorter then 5 minutes "
      "or went over midnight.\nThis is ${skippedReservations/(skippedReservations+totalReservations) * 100}%");*/

  Map<int, Map<int, List<Interval>>> dataSet = {};
  for(var i=1; i<=numberOfWeeks; i++) {
    dataSet.putIfAbsent(i, () => {});
  }

  //map to x week period
  //print("Mapping all these reservations to a ${numberOfWeeks} week period");

  selectedReservations.forEach((key, timeInterval) {
    var week = new Random().nextInt(numberOfWeeks) + 1;
    var day = timeInterval.from.weekday; //save the day of the week as reservation behavior depends on weekday

    //we are only interested in the time part and have filtered out reservations >24hours already
    var offset = timeInterval.till.day != timeInterval.from.day ? 1 : 0; //offset if we go past midnight
    var reservation = new Interval(new DateTime(2019, 1, 1, timeInterval.from.hour, timeInterval.from.minute, timeInterval.from.second),
        new DateTime(2019,1,1+offset, timeInterval.till.hour, timeInterval.till.minute, timeInterval.till.second));
    dataSet[week].putIfAbsent(day, () => []).add(reservation);

  });

  return new DataSet(dataSet);
}
Future<Solution> doEasyAssignment(int numberOfCars, DataSet dataSet) async {

  Zone zone = new Zone(numberOfCars);
  Solution solution = new Solution(dataSet.data.length);

  print("\nStarting an easy assignment of ${dataSet.totalReservations} reservations");

  for(var week=1; week<=dataSet.data.length; week++) {
    for(var day=1; day<=DateTime.DAYS_PER_WEEK; day++) {
      var dayList = dataSet.data[week][day];
      zone.flushJobs();

      if(dayList != null) {

        for(var reservation in dayList) {
          var car = zone.getAvailableCar(reservation);
          var c = car == null ? null : car.toString();
          solution.addCarAssignment(week, day, reservation, c);

          if(car != null) {
            car.useCar(reservation);
          }
        }
      }
    }
  }
  print("With ${numberOfCars} cars service level is ${solution.serviceLevel}%");
  print("These ${numberOfCars} cars were active for a total time of ${solution.totalCarUsageTime.toString()}");
  print("${solution.nonAssignedTime.toString()} could not be assigned.");
  //print("Sum of these is: ${(solution.nonAssignedTime + solution.totalCarUsageTime).toString()}");

  return solution;
}

Future<Solution> doCspAssignment(int numberOfCars, DataSet dataSet) async {

  List<String> cars = new List<String>();
  for(var i=0; i<numberOfCars; i++) {
    cars.add("car${i}");
  }

  print("\nStarting a csp assignment of ${dataSet.totalReservations} reservations");
  Solution solution = new Solution(dataSet.data.length);

  for(var week=1; week<=dataSet.data.length; week++) {
    for(var day=1; day<=DateTime.DAYS_PER_WEEK; day++) {
      var dayList = dataSet.data[week][day];
      print("week${week} day${day}: ${dayList?.length} reservations");

      if(dayList != null) {

        var assignment = null;
        var lastConsistentAssignment = {};
        var cspReservationsList = new List<Interval>();

        for(var reservation in dayList) {
          lastConsistentAssignment = assignment != null ? assignment : lastConsistentAssignment;

          cspReservationsList.add(reservation);
          Map domains = {};
          for(var r in cspReservationsList) {
            domains[r] = new List<String>.from(cars);
          }
          CSP dayCSP = new CSP(cspReservationsList, domains);

          for(var i=0; i<cspReservationsList.length; i++) {
            for(var j=i+1; j<cspReservationsList.length; j++) {
              dayCSP.addBinaryConstraint(new ReservationConstraint(cspReservationsList[i], cspReservationsList[j]));
            }
          }
          assignment = await backtrackingSearch(dayCSP, {});
          if(assignment == null) {
            cspReservationsList.remove(reservation);
            solution.addCarAssignment(week, day, reservation, null);
          }
        }
        assignment = assignment == null ? lastConsistentAssignment : assignment;

        for(var r in assignment.keys) {
          solution.addCarAssignment(week, day, r, assignment[r]);
        }
      }
    }
  }

  print("With ${numberOfCars} cars service level is ${solution.serviceLevel}%");
  print("These ${numberOfCars} cars were active for a total time of ${solution.totalCarUsageTime.toString()}");
  print("${solution.nonAssignedTime.toString()} could not be assigned.");
  //print("Sum of these is: ${(solution.nonAssignedTime + solution.totalCarUsageTime).toString()}");
  return solution;
}

Future<Null> createNewReservationsFile() async {
  var startDate = new DateTime(2019, 1, 1); //starting date of where we start selecting existing reservations
  var endDate = new DateTime(2019, 6, 30);
  var reservationDetails = await getDataFromFirebase(startDate, endDate);
  await writeReservationDetailsToFile(reservationDetails, "reservations");
}

Future<Map<String, dynamic>> readReservationDetailsFromFile(var fileName) async {
  var file = new File(fileName);
  var content = await file.readAsString();
  var map = JSON.decode(content);
  print("done reading file");
  return map;
}