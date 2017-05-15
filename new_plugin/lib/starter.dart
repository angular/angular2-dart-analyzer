// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:isolate';

import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/starter.dart';
import 'package:angular_analysis_plugin/plugin.dart';

void start(List<String> args, SendPort sendPort) {
  new ServerPluginStarter(
          new AngularAnalysisPlugin(PhysicalResourceProvider.INSTANCE))
      .start(sendPort);
}
