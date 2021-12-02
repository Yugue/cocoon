// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

typedef SetReleaseData = void Function(bool data);

class SwitchButton extends StatelessWidget {
  const SwitchButton({
    Key? key,
    required this.value,
    required this.modifyValue,
  }) : super(key: key);

  final bool value;
  final SetReleaseData modifyValue;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Lights'),
      value: value,
      onChanged: (bool value) {
        modifyValue(value);
      },
      secondary: const Icon(Icons.lightbulb_outline),
    );
  }
}
