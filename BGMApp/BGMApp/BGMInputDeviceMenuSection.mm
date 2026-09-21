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
//  BGMInputDeviceMenuSection.mm
//  BGMApp
//
//  Shows the physical input devices in BGMApp's main menu and sets the
//  system's default input device when one is selected. This is independent
//  of BGMApp's physical output playthrough and does not change BGMDevice's
//  required virtual input path.
//

 // Self Include
#import "BGMInputDeviceMenuSection.h"

// Local Includes
#import "BGM_Utils.h"
#import "BGM_Types.h"
#import "BGMAudioDevice.h"

// PublicUtility Includes
#import "CAAutoDisposer.h"
#import "CAHALAudioSystemObject.h"
#import "CAPropertyAddress.h"


#pragma clang assume_nonnull begin

static NSInteger const kInputDeviceMenuItemTag = 6;

@implementation BGMInputDeviceMenuSection {
    NSMenu* bgmMenu;
    NSMutableArray<NSMenuItem*>* inputDeviceMenuItems;
    // Called when a CoreAudio property has changed and we might need to update the menu. For
    // example, when a device is connected or disconnected, or the default input device changes.
    AudioObjectPropertyListenerBlock refreshNeededListener;
}

- (instancetype) initWithBGMMenu:(NSMenu*)inBGMMenu {
    if ((self = [super init])) {
        bgmMenu = inBGMMenu;
        inputDeviceMenuItems = [NSMutableArray new];

        [self listenForChanges];
        [self populateBGMMenu];
    }

    return self;
}

- (void) dealloc {
    // Tell CoreAudio not to call the listener block anymore. This probably isn't necessary.
    auto removeListener = [&] (AudioObjectPropertySelector prop) {
        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            CAHALAudioSystemObject().RemovePropertyListenerBlock(CAPropertyAddress(prop),
                                                                dispatch_get_main_queue(),
                                                                refreshNeededListener);
        });
    };

    removeListener(kAudioHardwarePropertyDevices);
    removeListener(kAudioHardwarePropertyDefaultInputDevice);
}

- (void) listenForChanges {
    BGMInputDeviceMenuSection* __weak weakSelf = self;

    refreshNeededListener = ^(UInt32 inNumberAddresses,
                              const AudioObjectPropertyAddress* inAddresses) {
        #pragma unused (inNumberAddresses, inAddresses)

        BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
            [weakSelf populateBGMMenu];
        });
    };

    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        // Refresh when devices are connected or disconnected.
        CAHALAudioSystemObject().AddPropertyListenerBlock(
            CAPropertyAddress(kAudioHardwarePropertyDevices),
            dispatch_get_main_queue(),
            refreshNeededListener);
        // Refresh when the default input device changes (e.g. changed in System Settings).
        CAHALAudioSystemObject().AddPropertyListenerBlock(
            CAPropertyAddress(kAudioHardwarePropertyDefaultInputDevice),
            dispatch_get_main_queue(),
            refreshNeededListener);
    });
}

- (void) populateBGMMenu {
    BGMAssert([NSThread isMainThread],
              "BGMInputDeviceMenuSection::populateBGMMenu called on non-main thread");

    // Remove existing menu items.
    for (NSMenuItem* item in inputDeviceMenuItems) {
        DebugMsg("BGMInputDeviceMenuSection::populateBGMMenu: Removing %s",
                 item.description.UTF8String);
        [bgmMenu removeItem:item];
    }

    [inputDeviceMenuItems removeAllObjects];

    // Add a menu item for each input device.
    CAHALAudioSystemObject audioSystem;
    UInt32 numDevices = audioSystem.GetNumberAudioDevices();

    if (numDevices > 0) {
        CAAutoArrayDelete<AudioObjectID> devices(numDevices);
        audioSystem.GetAudioDevices(numDevices, devices);

        for (UInt32 i = 0; i < numDevices; i++) {
            [self insertMenuItemForDevice:devices[i]];
        }
    }
}

- (BOOL) deviceCanBeInputDevice:(BGMAudioDevice)device {
    BOOL eligible = NO;

    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        CFStringRef uid = device.CopyDeviceUID();

        if (uid != nullptr) {
            bool isNullDevice = CFEqual(uid, CFSTR(kBGMNullDeviceUID));
            CFRelease(uid);

            eligible = !isNullDevice &&
                       !device.IsBGMDeviceInstance() &&
                       !device.IsHidden() &&
                       device.GetTotalNumberChannels(/* inIsInput = */ true) > 0 &&
                       device.CanBeDefaultDevice(/* inIsInput = */ true,
                                                 /* inIsSystem = */ false);
        }
    });

    return eligible;
}

- (void) insertMenuItemForDevice:(BGMAudioDevice)device {
    if (![self deviceCanBeInputDevice:device]) {
        return;
    }

    // Insert menu items after the item for the "Input Device" heading.
    const NSInteger menuItemIdx = [bgmMenu indexOfItemWithTag:kInputDeviceMenuItemTag] + 1;

    NSMenuItem* __nullable item = nil;

    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        item = [self createMenuItemForDevice:device];
    });

    if (item != nil) {
        DebugMsg("BGMInputDeviceMenuSection::insertMenuItemForDevice: Inserting %s",
                 item.description.UTF8String);
        [bgmMenu insertItem:BGMNN(item) atIndex:menuItemIdx];
        [inputDeviceMenuItems addObject:BGMNN(item)];
    }
}

- (NSMenuItem*) createMenuItemForDevice:(CAHALAudioDevice)device {
    NSString* title = CFBridgingRelease(device.CopyName());
    if (!title) {
        title = @"";
    }

    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:BGMNN(title)
                                                  action:@selector(inputDeviceMenuItemSelected:)
                                           keyEquivalent:@""];

    // Check the menu item for the current default input device.
    BOOL isSelected = NO;

    BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        AudioObjectID defaultInputDevice =
            CAHALAudioSystemObject().GetDefaultAudioDevice(/* inIsInput = */ true,
                                                           /* inIsSystem = */ false);
        isSelected = (defaultInputDevice == device.GetObjectID());
    });

    item.state = (isSelected ? NSOnState : NSOffState);
    item.target = self;
    item.indentationLevel = 1;
    item.representedObject = @{ @"deviceID": @(device.GetObjectID()) };

#if __clang_major__ >= 9
    if (@available(macOS 10.10, *)) {
        // Used for UI tests.
        item.accessibilityIdentifier = @"input-device";
    }
#endif

    return item;
}

- (void) inputDeviceMenuItemSelected:(NSMenuItem*)menuItem {
    DebugMsg("BGMInputDeviceMenuSection::inputDeviceMenuItemSelected: '%s' menu item selected",
             [menuItem.title UTF8String]);

    // Make sure the menu item is actually for an input device.
    if (![inputDeviceMenuItems containsObject:menuItem]) {
        return;
    }

    AudioDeviceID newDeviceID = [[menuItem representedObject][@"deviceID"] unsignedIntValue];
    NSString* deviceName = menuItem.title;

    // Dispatched because CoreAudio calls can block.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self changeToInputDevice:newDeviceID deviceName:deviceName];
    });
}

- (void) changeToInputDevice:(AudioDeviceID)deviceID deviceName:(NSString*)deviceName {
    // Set the systemwide default input device. This is independent of BGMApp's physical output
    // playthrough.
    OSStatus err = BGM_Utils::LogAndSwallowExceptions(BGMDbgArgs, [&] {
        CAHALAudioSystemObject().SetDefaultAudioDevice(/* inIsInput = */ true,
                                                       /* inIsSystem = */ false,
                                                       deviceID);
    });

    if (err != noErr) {
        // Couldn't change the input device, so show a warning. (No need to change the menu
        // selection back because it gets repopulated every time it's opened.)

        // NSAlerts should only be shown on the main thread.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"Failed to set input device: %@", deviceName);

            NSAlert* alert = [NSAlert new];

            alert.messageText =
                [NSString stringWithFormat:@"Failed to set %@ as the input device.", deviceName];
            alert.informativeText = @"This is probably a bug. Feel free to report it.";

            [alert runModal];
        });
    }
}

@end

#pragma clang assume_nonnull end
