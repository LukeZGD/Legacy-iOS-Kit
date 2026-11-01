//
//  jailbreak.h
//  socket
//
//  Created by staturnz on 2/27/26.
//

#ifndef jailbreak_h
#define jailbreak_h

#include <stdio.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <Foundation/Foundation.h>

#define JB_FLAG_NONE        0x00000000
#define JB_FLAG_BOOTSTRAP   0x00000001
#define JB_FLAG_TWEAKS      0x00000002
#define JB_FLAG_RESPRING    0x00000004
#define JB_FLAG_UNTETHER    0x00000008

#define ZEBRA_SOURCES_PATH "/var/mobile/Library/Application Support/xyz.willy.Zebra"
#define ZEBRA_SOURCES_FILE "/var/mobile/Library/Application Support/xyz.willy.Zebra/sources.list"
#define APT_TELESPHOREO_REPO "deb http://apt.saurik.com/ ios/1349.70 main"
#define APT_BIGBOSS_REPO "deb http://apt.thebigboss.org/repofiles/cydia/ stable main"
#define APT_MODMYI "deb http://modmyi.saurik.com/ stable main"
#define APT_CHARIZ_REPO "deb https://repo.chariz.com/ ./"
#define APT_PACKIX_REPO "deb https://repo.packix.com/ ./"
#define APT_HAVOC_REPO "deb https://havoc.app/ ./"
#define APT_ZEBRA_REPO "deb https://getzbra.com/repo ./"
#define APT_LUKEZGD_REPO "deb https://lukezgd.github.io/repo ./"

#endif /* jailbreak_h */
