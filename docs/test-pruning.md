# Test pruning with coverage protection

On 2026-11-01, removed 38 of 190 test functions (20%): Swift 171 → 137, Python 19 → 15. Count each Swift `@Test` function and Python `test_*` method once; parameterized arguments and loop iterations are not separate functions. Parameter matrices, opt-in checks, and retained assertions were not shortened to meet the target.

Prioritize duplicated leaf assertions already exercised by broader source/model/native fixtures, superseded lifecycle filtering, and standard argparse/default checks. Keep races, real persistence failures, native gestures/rendering, transport framing, and all installed-source/performance opt-ins. Each removal below identifies surviving regression evidence; this is a risk-based reduction, not a claim that every removed assertion is identical to a surviving one.

## Measured result

The baseline suite was taken from `95bdac6` and instrumented with the same coverage-capable launcher used for the reduced suite, Apple Swift 6.4 on arm64. All 19 Swift production files and the six Python tooling scripts use identical before/after denominators. No application source changed. The [machine-readable metrics](test-pruning-metrics.json) record counts, per-module metrics, baseline commit, and a SHA-256 fingerprint of the ordered Swift source paths/content.

| Metric | Before | After | Drop in percentage points |
| --- | ---: | ---: | ---: |
| Swift production lines | 4168/5560 (74.96%) | 4156/5560 (74.75%) | 0.22 |
| Swift production regions | 2307/3097 (74.49%) | 2287/3097 (73.85%) | 0.65 |
| Swift production functions | 893/1183 (75.49%) | 889/1183 (75.15%) | 0.34 |
| Python production lines | 239/555 (43.06%) | 239/555 (43.06%) | 0.00 |

Swift line coverage drops 0.22 percentage points, within the 2-point limit (also below 2% relative loss). CanvasCore line coverage changes from 96.02% to 95.16% (0.87 points); native application line coverage remains 68.24%. Every reported module's line/region/function loss is below 2 percentage points. The 12 lost lines are confined to core model code, including the unused legacy `CanvasVisibility.includesLifecycle` helper and invalid-region validation paths. Retained classifier, collision, and save-failure fixtures cover current behavior; reduced line coverage does not prove every removed edge assertion survives. Application startup and the probe remain included even where unexecuted. For the three Python tools imported by unittest, coverage stays 239/320 (74.69%); unexecuted probe/toolchain scripts remain included in the all-script figure.

Keep `incompleteAppendDoesNotCreateAResult`: it contributes 19 rollout-reader lines. The direct stale-revision rejection regression also remains; a duplicate translated-growth fixture was removed instead.

## Verification and reproduction

Run unfiltered fixture coverage through the authorized launcher:

```sh
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py test --enable-code-coverage
python3 -B -m unittest discover -s scripts/tests -v
```

The Swift run reports 98 runtime and 39 core test functions; eight installed-source/performance functions are skipped, leaving 129 enabled functions (with their parameter cases). All ordinary checks pass. The 15 remaining Python methods pass. Native fixture rendering/interactions execute against temporary models/windows; no installed desktop observation is enabled. Existing installed-source, live, huge-text interaction, and hosted acceptance gates retain their prior status.

The launcher writes `.build/verification/coverage.json`. SwiftPM's default JSON on this toolchain contained only the final core bundle; the launcher therefore passes every `.xctest/Contents/MacOS/*` binary plus `SessionCanvasProbe` to `llvm-cov export` using the merged `default.profdata`. Aggregate each production file's `summary.lines`, `summary.regions`, and `summary.functions` counts/covered counts; exclude Tests/generated code and retain all Sources files. Comparing a filtered run to an unfiltered baseline is invalid.

For an independent baseline repeat, use the baseline test files from the recorded commit with the same coverage launcher and unchanged production sources, run the same unfiltered command, and snapshot its JSON before running the reduced suite. Require the same file set and counts before comparing percentages. Local raw before/after exports and comparison snapshots are under `.build/verification/`; the committed metrics provide the compact result.

Python was measured with the standard-library `trace` module (no additional dependency), using identical launcher source in both runs and restoring the 19 baseline test methods for the baseline measurement:

```sh
python3 -B -m trace --count --coverdir .build/verification/python-covers --file .build/verification/python.trace --module unittest discover -s scripts/tests
```

Use a fresh counts file for each measurement. Count executable lines from `trace._find_executable_linenos` for every `scripts/*.py` file and lines with a positive trace count, excluding tests and standard-library/dependency files. The launcher coverage-export path is exercised by the actual instrumented Swift run; its Python unittest line coverage is measured separately.

## Removal decisions and retained evidence

| Removed function | Retained regression | Reason |
| --- | --- | --- |
| `testAcknowledgingOlderResultDoesNotDismissNewerOne` | [`displayedOlderResultCannotAcknowledgeNewerResult`](../Tests/CanvasRuntimeTests/CanvasRuntimeTests.swift) | The runtime regression checks the actual acknowledgment action and both result identities. |
| `testAcknowledgmentCannotClearNewExecutionOrPermission` | [`acknowledgmentIsRejectedOutsideFinished`](../Tests/CanvasRuntimeTests/CanvasRuntimeTests.swift) | The runtime matrix covers every ineligible state and persisted acknowledgments. |
| `testCompletedQuestionIsNotBlockingInput` | [`onlyVerifiedDialogueAndTerminalEvidenceAreDisplayed`](../Tests/CanvasCoreTests/RolloutReaderTests.swift) | Retain a terminal question in dialogue plus source terminal-state checks. |
| `testDatabaseRestoresWorkspaceAndIsolatesSources` | [`legacyMigrationAndVersionedRoundTrip`](../Tests/CanvasCoreTests/SessionLayerTests.swift) | The retained migration round trip and runtime visibility/acknowledgment restart tests cover source isolation. |
| `testDiscoveryDoesNotMoveExistingNotesOrMergeSameTitles` | [`occupiedCreationStaysNearTheClickAcrossRefreshAndRestart`](../Tests/CanvasRuntimeTests/ProjectCreationTests.swift) | Retain exact existing/new placements through creation, refresh, and restart, plus structured inventory identity checks. |
| `testEachFailureAndStopNeedsReview` | [`historyOnlyPromotesTheLatestTerminalTurn`](../Tests/CanvasRuntimeTests/ImportRegressionTests.swift) | The source regression exercises completed, failed, and interrupted terminal turns. |
| `testExternalMembershipChangeRelocatesOnlyAffectedNote` | [`externalDesktopMovesRemainAuthoritativeOverStaleBackend`](../Tests/CanvasRuntimeTests/ProjectMembershipTests.swift) | The source regression exercises reassignment, removal, and identity preservation. |
| `testFreshSessionIsIdleAndEmptyTitleHasFallback` | [`blankNameAndDirectoryCreateAProjectlessResumableSession`](../Tests/CanvasRuntimeTests/ProjectCreationTests.swift) | Creation fixtures exercise defaults through the production source. |
| `testHistoryExcludesToolPayloadsAndRetainsResultIdentity` | [`viewerRequestsSummaryPagesNewestFirstAndLoadsOlderOnlyOnDemand`](../Tests/CanvasRuntimeTests/ImportRegressionTests.swift) | The viewer regression verifies tool-output exclusion and stable result identities across pages. |
| `testLargeProjectGrowsWithoutMisclassifyingMembers` | [`layeredBatchArrivalIncludesFilteredObstaclesAndSurvivesReopening`](../Tests/CanvasCoreTests/DownwardGrowthTests.swift) | The newer anchored-growth fixture covers batch arrivals, membership, obstacles, and persistence. |
| `testPartialOverlapDoesNotChooseProject` | [`testRegionBordersAreUnassigned`](../Tests/CanvasCoreTests/CanvasCoreTests.swift) | Retain explicit center/border checks and native project-context geometry tests. |
| `testReadOnlyStorageFailureIsNotReportedAsAcknowledged` | [`bulkFailureRollsBackAndUnreadFailurePreservesAcknowledgment`](../Tests/CanvasRuntimeTests/AcknowledgmentActionsTests.swift) | The old test only opened an invalid path; retained SQL-trigger fixtures verify real write failures. |
| `testRegionCannotShrinkPastMemberOrMinimum` | [`projectsWithHiddenMembersCanLeaveBlockedOriginsAndInvalidGeometryIsRejected`](../Tests/CanvasCoreTests/CanvasRearrangerTests.swift) | Retain invalid-geometry and transactional runtime edit checks. |
| `testRegionMoveMustNotSweepNonmembersOrOverlap` | [`overviewProjectGesturesRetainNavigationCancellationAndCollisionRules`](../Tests/CanvasRuntimeTests/SemanticZoomTests.swift) | Retain native collision/cancellation checks and whole-layout validation. |
| `testViewportRoundTripSupportsNegativeCoordinates` | [`testZoomPreservesPointUnderCursor`](../Tests/CanvasCoreTests/CanvasCoreTests.swift) | The retained focal-zoom invariant and native context-menu fixtures exercise coordinate conversion. |
| `testWireNeverTreatsUnloadedAsIdle` | [`desktopRuntimeOverridesUnloadedInventoryAndUpdatesWithoutManualRefresh`](../Tests/CanvasRuntimeTests/LiveStateTests.swift) | Retain the production adapter check against unloaded inventory and live evidence. |
| `testWireTerminalResultsAreStableAndInProgressIsNotFinished` | [`historyOnlyPromotesTheLatestTerminalTurn`](../Tests/CanvasRuntimeTests/ImportRegressionTests.swift) | Retain terminal and nonterminal source-history matrices with result identities. |
| `hiddenMembersTravelWithTheirProjectAndVisibleOverlapsAreRepaired` | [`rearrangeUsesVisibleProjectionAndPersistsWithoutChangingSourceFactsOrViewport`](../Tests/CanvasRuntimeTests/RearrangeTests.swift) | The runtime regression verifies carried hidden members, overlap repair, and persistence. |
| `noVisibleSessionsDoesNotChangeGeometry` | [`layoutSaveFailureKeepsTheOriginalWorkspaceAndEmptyProjectionIsDisabled`](../Tests/CanvasRuntimeTests/RearrangeTests.swift) | The application-level check rejects empty projections and preserves geometry. |
| `aFreeNoteInTheNextRowIsPushedInsteadOfSkippingTheRow` | [`aPushedFreeNoteCanPushAHorizontallyOffsetProject`](../Tests/CanvasCoreTests/DownwardGrowthTests.swift) | The retained cascade fixture checks the same next-row allocation and free-note displacement plus another project. |
| `growthDoesNotDependOnWorldOrigin` | [`occupiedCreationStaysNearTheClickAcrossRefreshAndRestart`](../Tests/CanvasRuntimeTests/ProjectCreationTests.swift) | Drop a duplicate translated copy of the growth fixture; retain negative-world-coordinate creation/obstacle checks and exact cascade geometry. |
| `sixSquaresPreferACompactBlockOverARibbon` | [`unassignedGridUsesPhysicalCardProportionsAndGrowsWithTheCount`](../Tests/CanvasCoreTests/CanvasRearrangerTests.swift) | Retain compact six-card and large-grid checks plus mixed rectangle packing. |
| `wrongSessionIdentityIsRejected` | [`discoverySummaryUsesLatestTerminalEvidenceAndRejectsLaterWork`](../Tests/CanvasCoreTests/RolloutReaderTests.swift) | The retained reader fixture rejects mismatched identity through the production entry point. |
| `lifecycleHidingRequiresKnownIdleAndAcknowledgedResult` | [`allCutoffsAndProtections`](../Tests/CanvasCoreTests/SessionLayerTests.swift) | The old includesLifecycle helper is superseded by the current layer classifier. |
| `unknownAgeHidingDefaultsOnAndPreservesWorkAndUnreviewedResults` | [`classificationIsExclusiveAndExhaustive`](../Tests/CanvasCoreTests/SessionLayerTests.swift) | Unknown now belongs to Inactive independent of age; retain current layer and legacy-payload tests. |
| `openingAndAcknowledgingPersistsOnlyExplicitReview` | [`acknowledgeAllIncludesHiddenFinishedAndPreservesNewResultsAcrossRestart`](../Tests/CanvasRuntimeTests/AcknowledgmentActionsTests.swift) | Retain restart persistence, explicit viewer actions, and ineligible-state acknowledgment checks. |
| `archivedUnknownSessionsStayInactiveIndependentlyOfAgeAndUnreadEvidence` | [`classificationIsExclusiveAndExhaustive`](../Tests/CanvasCoreTests/SessionLayerTests.swift) | Retain archived-state priority, exhaustive classification, and source-wide layer count/filter checks. |
| `emptyAndHiddenProjectsLeaveOverviewAccessibilityAndFitBounds` | [`overviewFitAndAccessibilityAreExclusiveAndRestoreIndependentViewports`](../Tests/CanvasRuntimeTests/LayerInteractionTests.swift) | Retain native overview/accessibility/empty-layer fit checks and composable visibility filters. |
| `creationFromInactiveUsesActiveCounterpartAndPreservesInactiveLayout` | [`creationRevealsItsSessionEvenWhenUnknownIsHidden`](../Tests/CanvasRuntimeTests/ProjectCreationTests.swift) | The retained creation matrix covers project and projectless creation from Active and Inactive. |
| `hiddenCurrentMembersTravelButOtherLayersDoNotAndOverlapIsRejected` | [`draggingAnOverviewMovesTheProjectAndAllMembersWithoutPanning`](../Tests/CanvasRuntimeTests/SemanticZoomTests.swift) | Retain native hidden-member dragging, other-layer isolation, and collision fixtures. |
| `invalidExplicitDirectoryDoesNotCreateOrReplaceIt` | [`creationFailureRemainsInItsDialog`](../Tests/CanvasRuntimeTests/ProjectCreationTests.swift) | The retained application fixture exercises invalid-directory failure and user-visible error placement. |
| `namingFailureRetainsOneConfirmedSession` | [`unverifiedCreationReportsWarningWithoutAutomaticNavigation`](../Tests/CanvasRuntimeTests/ProjectCreationTests.swift) | The retained application fixture exercises the same naming failure and single retained session. |
| `serverMembershipImportsBeforeDesktopAssignmentIsSaved` | [`createsWithConfirmedServerProjectAndRetainsEmptyThread`](../Tests/CanvasRuntimeTests/ProjectCreationTests.swift) | Retain created-session membership import and authoritative desktop unassignment fixtures. |
| `backendConfirmationCannotStandInForDesktopMembership` | [`unavailableMovesPreserveLocalGeometryAndExposeDisabledMenu`](../Tests/CanvasRuntimeTests/ProjectMembershipTests.swift) | Retain rejected writes/unchanged geometry and stale backend confirmation restart matrices. |
| `test_local_build_defaults_remain_available` | [`test_versioned_bundle_preserves_executable_and_minimum_os`](../scripts/tests/test_release_packaging.py) | Remove a parser-default assertion; retain actual bundle metadata/signature and archive checks. |
| `test_arbitrary_command_options_are_rejected` | [`test_live_desktop_cannot_be_enabled_for_a_broad_run`](../scripts/tests/test_verify_local.py) | Remove a standard argparse unknown-option check; retain pre-subprocess safety rejection tests. |
| `test_layer_preview_accepts_one_layer_and_rejects_combined_mode` | [`test_preview_defaults_to_demo_and_never_uses_shell`](../scripts/tests/test_verify_local.py) | Remove a direct argparse choices check; retain preview execution and safe command construction. |
| `test_outputs_reject_user_database_and_wrong_extension` | [`test_invalid_output_is_rejected_before_subprocesses`](../scripts/tests/test_verify_local.py) | Retain production-path rejection at the launcher boundary and symlink escape validation. |

Earlier test counts and removed names in historical [verification evidence](../openspec/changes/add-session-canvas/verification.md) describe those earlier revisions. Current requirements and measurement behavior are in [local-verification](../openspec/changes/add-session-canvas/specs/local-verification/spec.md).
