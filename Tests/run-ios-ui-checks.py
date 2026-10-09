#!/usr/bin/env python3
"""Run isolated iOS UI regressions without changing the user's Xcode project or ledger."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

EXTRA_OBJECTS = r'''
B00000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NavigationAppearanceUITests.swift; sourceTree = "<group>"; };
B00000000000000000000002 = {isa = PBXBuildFile; fileRef = B00000000000000000000001; };
B00000000000000000000003 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = RegressionUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
B00000000000000000000005 = {isa = PBXNativeTarget; buildConfigurationList = B0000000000000000000000B; buildPhases = (B00000000000000000000006, B00000000000000000000007, B00000000000000000000008); buildRules = (); dependencies = (B0000000000000000000000D); name = RegressionUITests; productName = RegressionUITests; productReference = B00000000000000000000003; productType = "com.apple.product-type.bundle.ui-testing"; };
B00000000000000000000006 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (B00000000000000000000002); runOnlyForDeploymentPostprocessing = 0; };
B00000000000000000000007 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
B00000000000000000000008 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
B00000000000000000000009 = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.modest.AssetFlow.Regression.UITests; PRODUCT_NAME = "$(TARGET_NAME)"; TEST_TARGET_NAME = AssetFlow; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2";}; name = Debug; };
B0000000000000000000000A = {isa = XCBuildConfiguration; buildSettings = {CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.modest.AssetFlow.Regression.UITests; PRODUCT_NAME = "$(TARGET_NAME)"; TEST_TARGET_NAME = AssetFlow; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2";}; name = Release; };
B0000000000000000000000B = {isa = XCConfigurationList; buildConfigurations = (B00000000000000000000009, B0000000000000000000000A); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
B0000000000000000000000C = {isa = PBXContainerItemProxy; containerPortal = A00000000000000000000001; proxyType = 1; remoteGlobalIDString = A00000000000000000000005; remoteInfo = AssetFlow; };
B0000000000000000000000D = {isa = PBXTargetDependency; target = A00000000000000000000005; targetProxy = B0000000000000000000000C; };


'''
SCHEME = r'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="AssetFlow.app" BlueprintName="AssetFlow" ReferencedContainer="container:UIRegression.xcodeproj"/></BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="B00000000000000000000005" BuildableName="RegressionUITests.xctest" BlueprintName="RegressionUITests" ReferencedContainer="container:UIRegression.xcodeproj"/></BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="B00000000000000000000005" BuildableName="RegressionUITests.xctest" BlueprintName="RegressionUITests" ReferencedContainer="container:UIRegression.xcodeproj"/></TestableReference></Testables></TestAction>
</Scheme>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-id", required=True, help="UDID of a booted iOS simulator")
    parser.add_argument("--work-dir", type=Path, help="New scratch directory for build logs and xcresult bundles")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    work = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix="assetflow-ui-"))
    work.mkdir(parents=True, exist_ok=True)
    if any(work.glob("*.xcresult")):
        parser.error("Use a fresh work directory so previous results are preserved")
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    project = work / "UIRegression.xcodeproj"
    project.mkdir(exist_ok=True)
    pbx = (root / "AssetFlow.xcodeproj/project.pbxproj").read_text()
    source = 'path = AssetFlow; sourceTree = "<group>";'
    if source not in pbx:
        raise RuntimeError("The app source group changed; update this isolated test harness")
    pbx = pbx.replace(source, f'path = "{root / "AssetFlow"}"; sourceTree = "<absolute>";')
    pbx = pbx.replace("com.modest.AssetFlow;", "com.modest.AssetFlow.Regression;")
    pbx = pbx.replace("objects = {", "objects = {" + EXTRA_OBJECTS, 1)
    pbx = pbx.replace("targets = (", "targets = (\nB00000000000000000000005,", 1)
    pbx = pbx.replace("children = (", "children = (\nB00000000000000000000001,\nB00000000000000000000003,", 1)
    (project / "project.pbxproj").write_text(pbx)
    schemes = project / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / "UIRegression.xcscheme").write_text(SCHEME)
    shutil.copyfile(root / "Tests/NavigationAppearanceUITests.swift", work / "NavigationAppearanceUITests.swift")
    appearance_command = ["xcrun", "simctl", "ui", args.device_id, "appearance"]
    original = subprocess.check_output(appearance_command, env=env, text=True).strip()
    print(f"Isolated UI test results: {work}", flush=True)
    try:
        for appearance, tests in [
            ("light", ["testFollowSystemLight", "testPendingNavigationAndDeleteLast"]),
            ("dark", ["testFollowSystemDark"]),
        ]:
            subprocess.run(appearance_command + [appearance], env=env, check=True)
            command = [
                "xcodebuild", "test", "-project", str(project), "-scheme", "UIRegression",
                "-destination", f"platform=iOS Simulator,id={args.device_id}",
                "-derivedDataPath", str(work / "DerivedData"),
                "-resultBundlePath", str(work / f"{appearance}.xcresult"),
                "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG",
            ] + [f"-only-testing:RegressionUITests/NavigationAppearanceUITests/{test}" for test in tests]
            log = work / f"test-{appearance}.log"
            print(f"Running {appearance}: {', '.join(tests)}", flush=True)
            with log.open("w") as output:
                result = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT)
            if result.returncode:
                print("\n".join(log.read_text().splitlines()[-50:]))
                raise SystemExit(result.returncode)
            print(f"Passed: {appearance}", flush=True)
    finally:
        subprocess.run(appearance_command + [original], env=env, check=True)


if __name__ == "__main__":
    main()
