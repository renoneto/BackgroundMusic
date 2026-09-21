// This file is part of Background Music.
//
// Background Music is free software: you can redistribute it and/or
// modify it under the terms of the GNU General Public License as
// published by the Free Software Foundation, either version 2 of the
// License, or (at your option) any later version.
//
// Background Music is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Background Music. If not, see <http://www.gnu.org/licenses/>.

//
//  BGMAppUITests.mm
//  BGMAppUITests
//
//  Copyright © 2017, 2018, 2020, 2022 Kyle Neideck
//
//  You might want to use Xcode's UI test recording feature if you add new tests.
//

// Local Includes
#import "BGM_TestUtils.h"
#import "BGM_Types.h"
#import "BGM_Utils.h"
#import "BGMAudioDevice.h"
#import "BGMBackgroundMusicDevice.h"

// PublicUtility Includes
#import "CAHALAudioSystemObject.h"

// Scripting Bridge Includes
#import "BGMApp.h"

// System Includes
#import <XCTest/XCTest.h>


// TODO: Mock BGMDevice and music players.

#if __clang_major__ >= 9

@interface BGMAppUITests : XCTestCase
@end

@implementation BGMAppUITests {
    // The BGMApp instance.
    XCUIApplication* app;

    // Convenience vars.
    //
    // The menu bar icon. (Called the status bar icon in some places.)
    XCUIElement* icon;
    // The menu items in the main menu.
    XCUIElementQuery* menuItems;
}

- (void) setUp {
    [super setUp];
    
    // In UI tests it is usually best to stop immediately when a failure occurs.
    self.continueAfterFailure = NO;

    // Set up the app object and some convenience vars.
    app = [[XCUIApplication alloc] init];
    menuItems = app.menuBars.menuItems;
    icon = [app.menuBars childrenMatchingType:XCUIElementTypeStatusItem].element;

    // TODO: Make sure BGMDevice isn't set as the OS X default device before launching BGMApp.

    // Tell BGMApp not to load/store user defaults (settings) and to use
    // NSApplicationActivationPolicyRegular. If it used the "accessory" policy as usual, the tests
    // would fail to start because of a bug in Xcode.
    app.launchArguments = @[ @"--no-persistent-data", @"--show-dock-icon" ];

    // Make the "Background Music wants to use the microphone" dialog appear every time so the test
    // doesn't need logic to handle both cases.
    // TODO: Commented out until acceptMicrophoneAuthorizationDialog work again. See below.
    // if (@available(macOS 10.15.4, *)) {
    //     [app resetAuthorizationStatusForResource:XCUIProtectedResourceMicrophone];
    // }

    // Launch BGMApp.
    [app launch];

    // TODO: This doesn't seem to be working on macOS 12.4 (21F79). You can click OK manually for
    //       now.
    // [self acceptMicrophoneAuthorizationDialog];

    if (![icon waitForExistenceWithTimeout:20.0]) {
        // The status bar icon/button has this type when using older versions of XCTest, so try
        // both. (Actually, it might depend on the macOS or Xcode version. I'm not sure.)
        XCUIElement* iconOldType =
            [app.menuBars childrenMatchingType:XCUIElementTypeMenuBarItem].element;
        if ([iconOldType waitForExistenceWithTimeout:20.0]) {
            NSLog(@"icon = iconOldType");
            icon = iconOldType;
        }
    }

    // Wait for the initial elements.
    XCTAssert([app waitForExistenceWithTimeout:20.0]);
    XCTAssert([icon waitForExistenceWithTimeout:20.0]);
}

// Clicks the OK button in the "Background Music wants to use the microphone" dialog.
- (void) acceptMicrophoneAuthorizationDialog {
    XCUIApplication* unc =
        [[XCUIApplication alloc] initWithBundleIdentifier:@"com.apple.UserNotificationCenter"];
    NSLog(@"UserNotificationCenter: %@", unc);
    XCUIElement* okButton = unc.dialogs.buttons[@"OK"];

    XCTAssert([okButton waitForExistenceWithTimeout:20.0]);

    // This click is failing on GH Actions. No idea why, so try a sleep.
    (void)[XCTWaiter waitForExpectations:@[[XCTestExpectation new]] timeout:5.0];
    [okButton click];

    int retries = 10;
    while (retries > 0 && [okButton waitForExistenceWithTimeout:3.0]) {
        NSLog(@"Microphone authorization dialog is still open. Trying to click OK again.");
        [okButton click];
        retries--;
    }
}

- (void) tearDown {
    // Click the quit menu item.
    if (!menuItems.count) {
        [icon click];
    }

    [menuItems[@"Quit Background Music"] click];

    // BGMApp should quit.
    XCTAssertTrue([app waitForState:XCUIApplicationStateNotRunning timeout:10.0]);
    
    [super tearDown];
}

- (void) testCycleOutputDevices {
    const int NUM_CYCLES = 1;

    // sbApp lets us use AppleScript to query BGMApp and check the test has made the changes to its
    // settings we expect.
    BGMAppApplication* sbApp = [SBApplication applicationWithBundleIdentifier:@kBGMAppBundleID];

    // Get macOS to show the "'Xcode' wants to control 'Background Music'" dialog before we start
    // the test so it doesn't interrupt it.
    [[sbApp selectedOutputDevice] name];

    // Click the icon to open the main menu.
    [icon click];

    // Get the list of output devices from the main menu.
    // BGMOutputDeviceMenuSection::createMenuItemForDevice gives every output device menu item the
    // accessibility identifier "output-device" so we can find all of them here.
    NSArray<XCUIElement*>* outputDeviceMenuItems =
        [menuItems matchingIdentifier:@"output-device"].allElementsBoundByIndex;

    // For debugging certain issues, it can be useful to repeatedly switch between two
    // devices:
    // outputDeviceMenuItems = [outputDeviceMenuItems subarrayWithRange:NSMakeRange(0,2)];

    XCTAssertGreaterThan(outputDeviceMenuItems.count, 0);

    // Click the last device to close the menu again.
    [outputDeviceMenuItems.lastObject click];

    for (int i = 0; i < NUM_CYCLES; i++) {
        // Select each output device.
        for (XCUIElement* item in outputDeviceMenuItems) {
            [icon click];
            [item click];

            // Assert that the device we clicked is the selected device now.
            for (BGMAppOutputDevice* device in [sbApp outputDevices]) {
                // TODO: This seems a bit fragile. Would it still work with long device names?
                if ([device.name isEqualToString:[item title]]) {
                    XCTAssert(device.selected);
                } else {
                    XCTAssertFalse(device.selected);
                }
            }
        }
    }
}

- (void) testSelectInputDevice {
    CAHALAudioSystemObject audioSystem;

    // Remember the default input device so we can restore it at the end of the test.
    AudioObjectID originalInput = kAudioObjectUnknown;
    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        originalInput = audioSystem.GetDefaultAudioDevice(/* inIsInput = */ true,
                                                          /* inIsSystem = */ false);
    });

    // Click the icon to open the main menu.
    [icon click];

    // Get the list of input devices from the main menu.
    // BGMInputDeviceMenuSection::createMenuItemForDevice gives every input device menu item the
    // accessibility identifier "input-device" so we can find all of them here.
    NSArray<XCUIElement*>* inputDeviceMenuItems =
        [menuItems matchingIdentifier:@"input-device"].allElementsBoundByIndex;

    XCTAssertGreaterThan(inputDeviceMenuItems.count, 0);

    // Select each input device.
    for (XCUIElement* item in inputDeviceMenuItems) {
        [icon click];
        [item click];

        // The device we clicked should now be the system's default input device.
        AudioObjectID defaultInput = kAudioObjectUnknown;
        NSString* defaultInputName = nil;
        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            defaultInput = audioSystem.GetDefaultAudioDevice(/* inIsInput = */ true,
                                                             /* inIsSystem = */ false);
            defaultInputName =
                CFBridgingRelease(BGMAudioDevice(defaultInput).CopyName());
        });

        XCTAssertNotEqual(defaultInput, kAudioObjectUnknown);
        XCTAssertEqualObjects(defaultInputName, [item title]);
    }

    // Restore the original default input device.
    if (originalInput != kAudioObjectUnknown) {
        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            audioSystem.SetDefaultAudioDevice(/* inIsInput = */ true,
                                              /* inIsSystem = */ false,
                                              originalInput);
        });
    }
}

@end

#endif /* __clang_major__ >= 9 */

