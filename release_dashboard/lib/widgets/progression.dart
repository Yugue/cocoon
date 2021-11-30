// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'codesign_engine_substeps.dart';
import 'conductor_status.dart';
import 'create_release_substeps.dart';
import 'engine_cherrypicks_substeps.dart';
import 'substeps.dart';

/// Displays the progression and each step of the release from the conductor.
///
// TODO(Yugue): Add documentation to explain
// each step of the release, https://github.com/flutter/flutter/issues/90981.
class MainProgression extends StatefulWidget {
  const MainProgression({
    Key? key,
    this.previousCompletedStep,
  }) : super(key: key);

  final int? previousCompletedStep;

  @override
  State<MainProgression> createState() => MainProgressionState();

  static const List<String> _stepTitles = <String>[
    'Initialize a New Flutter Release',
    'Apply Engine Cherrypicks',
    'Codesign Engine Binaries',
    'Publish the Release',
    'Release is Successfully published'
  ];
}

class MainProgressionState extends State<MainProgression> {
  int _completedStep = 0;

  @override
  void initState() {
    /// Enables the stepper to resume from the step it was left on previously.
    if (widget.previousCompletedStep != null) {
      _completedStep = widget.previousCompletedStep!;
    }
    super.initState();
  }

  /// Move forward the stepper to the next step of the release.
  void nextStep() {
    if (_completedStep < MainProgression._stepTitles.length - 1) {
      setState(() {
        _completedStep += 1;
      });
    }
  }

  /// Change each step's state according to the current completed step.
  StepState handleStepState(int index) {
    if (_completedStep > index) {
      return StepState.complete;
    } else if (_completedStep == index) {
      return StepState.indexed;
    } else {
      return StepState.disabled;
    }
  }

  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Scrollbar(
        isAlwaysShown: true,
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          physics: const ClampingScrollPhysics(),
          children: <Widget>[
            const ConductorStatus(),
            const SizedBox(height: 20.0),
            Stepper(
              controlsBuilder: (BuildContext context, ControlsDetails details) => Row(),
              physics: const ScrollPhysics(),
              currentStep: _completedStep,
              onStepContinue: nextStep,
              steps: <Step>[
                Step(
                  title: Text(MainProgression._stepTitles[0]),
                  content: Column(
                    children: <Widget>[
                      CreateReleaseSubsteps(nextStep: nextStep),
                    ],
                  ),
                  isActive: true,
                  state: handleStepState(0),
                ),
                Step(
                  title: Text(MainProgression._stepTitles[1]),
                  content: Column(
                    children: <Widget>[
                      EngineCherrypicksSubsteps(nextStep: nextStep),
                    ],
                  ),
                  isActive: true,
                  state: handleStepState(1),
                ),
                Step(
                  title: Text(MainProgression._stepTitles[2]),
                  content: Column(
                    children: <Widget>[
                      CodesignEngineSubsteps(nextStep: nextStep),
                    ],
                  ),
                  isActive: true,
                  state: handleStepState(2),
                ),
                Step(
                  title: Text(MainProgression._stepTitles[3]),
                  content: Column(
                    children: <Widget>[
                      ConductorSubsteps(nextStep: nextStep),
                    ],
                  ),
                  isActive: true,
                  state: handleStepState(3),
                ),
                Step(
                  title: Text(MainProgression._stepTitles[4]),
                  content: Column(),
                  isActive: true,
                  state: handleStepState(4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
