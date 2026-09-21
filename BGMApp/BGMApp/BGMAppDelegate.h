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
//  BGMAppDelegate.h
//  BGMApp
//
//  Copyright © 2016, 2017, 2020 Kyle Neideck
//  Copyright © 2021 Marcus Wu
//
//  Sets up and tears down the app.
//

// System Includes
#import <Cocoa/Cocoa.h>

@class BGMAudioDeviceManager;
@class BGMAppVolumesController;

// Tag for the "About Background Music" item in MainMenu.xib.
static NSInteger const kAboutMenuItemTag = 4;

// Retained for compilation of the legacy BGMAppVolumes class, which positions per-app volume
// rows relative to this tag. BGMAppVolumes is no longer instantiated, so the value is unused
// at runtime.
static NSInteger const kSeparatorBelowVolumesMenuItemTag = 4;

@interface BGMAppDelegate : NSObject <NSApplicationDelegate>

@property (weak) IBOutlet NSMenu* bgmMenu;

// Kept for BGMAppDelegate+AppleScript (setMainVolume:). Not shown in the menu.
@property (weak) IBOutlet NSSlider* outputVolumeSlider;

@property (weak) IBOutlet NSPanel* aboutPanel;
@property (unsafe_unretained) IBOutlet NSTextView* aboutPanelLicenseView;

@property (weak) IBOutlet NSMenuItem* debugLoggingMenuItemUnwrapped;

@property (readonly) BGMAudioDeviceManager* audioDevices;

// Kept for BGMAppDelegate+AppleScript (applications). Not initialised; the per-app volume menu
// controls were intentionally removed.
@property BGMAppVolumesController* appVolumes;

@end

