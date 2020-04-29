/*
 * Copyright (C) 2009 by Matthias Ringwald
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holders nor the names of
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY MATTHIAS RINGWALD AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MATTHIAS
 * RINGWALD OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 */

/*
 *  Allows to inject mouse events into system event handler
 *  works with MouseSupport package
 */

#include "mouse_msgs.h"
#import "AppDelegate.h"

#include <strings.h>

#import <UIKit/UIKit.h>

static CFMessagePortRef mouseMessagePort = NULL;

int mouseOpen()
{
    // If the port is already open, open it
	if (!mouseMessagePort)
		mouseMessagePort = CFMessagePortCreateRemote(NULL, CFSTR(MessagePortName));

    // Tell SpringBoard to enable the mouse pointer
    if (mouseMessagePort) {
        BOOL enabled = YES;
        NSData *data = [NSData dataWithBytes:(void *)&enabled length:sizeof(BOOL)];
        CFMessagePortSendRequest(mouseMessagePort, MouseMessageTypeSetEnabled, (__bridge CFDataRef)data, 1, 0, NULL, NULL);
    }

	return (mouseMessagePort == NULL) ? kCFMessagePortIsInvalid : kCFMessagePortSuccess;
}

void mouseClose()
{
	if (mouseMessagePort) {
        // Tell SpringBoard to disable the mouse pointer
        BOOL enabled = NO;
        NSData *data = [NSData dataWithBytes:(void *)&enabled length:sizeof(BOOL)];
        CFMessagePortSendRequest(mouseMessagePort, MouseMessageTypeSetEnabled, (__bridge CFDataRef)data, 1, 0, NULL, NULL);

        // Close the mach port connection
        CFMessagePortInvalidate(mouseMessagePort);
        CFRelease(mouseMessagePort);
        mouseMessagePort = NULL;
    }
}

int mouseSendEvent(float x, float y, char buttons)
{
    int ret = kCFMessagePortIsInvalid;

    if (mouseMessagePort) {
        // Create and send message
        MouseEvent event;
        
        UIInterfaceOrientation orientation = [[AppDelegate sharedInstance] getOrientation];
        
        //saiyen
        //Get orientation, if orientation is landscape, switch x and y optionally invert
        UIScreen *screen = [UIScreen mainScreen];
        CGRect fullScreenRect = screen.bounds; //implicitly in Portrait orientation.        
        
        if (UIInterfaceOrientationIsLandscape(orientation))
        {
            CGRect temp;
            temp.size.width = fullScreenRect.size.height;
            temp.size.height = fullScreenRect.size.width;
            fullScreenRect = temp;      
        }

        if (orientation == UIDeviceOrientationLandscapeLeft) {
            event.x = fullScreenRect.size.height-y;
            event.y = x;
        }else if(orientation == UIDeviceOrientationLandscapeRight){
            event.x = y;
            event.y = fullScreenRect.size.width-x;
        }else if (orientation == UIDeviceOrientationPortraitUpsideDown) {
            event.x = fullScreenRect.size.width-x;
            event.y = fullScreenRect.size.height-y;
        }else{
            event.x = x;
            event.y = y;
        }
        //saiyen
        
        event.absolute = YES;
        event.buttons = buttons;

        NSData *data = [NSData dataWithBytes:(void *)&event length:sizeof(MouseEvent)];
        ret = CFMessagePortSendRequest(mouseMessagePort, MouseMessageTypeEvent, (__bridge CFDataRef)data, 1, 0, NULL, NULL);
    }

    return ret;
}
