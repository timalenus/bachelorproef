import 'package:firebase_dart/firebase_dart.dart';
import 'dart:io';
import 'dart:convert';
import 'package:partago_model/partago_model.dart';

createDataset() async {

  var ref = new Firebase("https://sizzling-torch-8026.firebaseio.com");
  await ref.authWithCustomToken("94Nfz8qtUw1wp78tVw2ksjExtQ2sqUfofmdDSfH9");

  Map<String,dynamic> carConfigs = await ref.child("carConfigs").orderByChild("group").equalTo("cvba").get();
}

