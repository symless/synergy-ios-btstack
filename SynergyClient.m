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

#import "SynergyClient.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <dlfcn.h>

//#import "../libactivator/libactivator.h"
#include "hid-support.h"

NSString *keyServerAddress = @"ServerAddress";
NSString *keyClientName    = @"ClientName";
NSString *keyHomeButtonHotkey = @"HomeButtonHotKey";
NSString *keyActivatorDefautsApplied = @"ActivatorDefaultsApplied";

const char*	 kMsgHello			= "Synergy%2i%2i";
const char*	 kMsgHelloBack		= "Synergy%2i%2i%s";
const char*	 kMsgCEnter 		= "CINN%2i%2i%4i%2i";
const char*	 kMsgCLeave 		= "COUT";
const char*	 kMsgCKeepAlive		= "CALV";
const char*	 kMsgDKeyDown		= "DKDN%2i%2i%2i";
const char*	 kMsgDKeyRepeat		= "DKRP%2i%2i%2i%2i";
const char*	 kMsgDKeyUp			= "DKUP%2i%2i%2i";
const char*	 kMsgDMouseDown		= "DMDN%1i";
const char*	 kMsgDMouseUp		= "DMUP%1i";
const char*	 kMsgDMouseMove		= "DMMV%2i%2i";
const char*	 kMsgQInfo			= "QINF";
const char*	 kMsgDInfo			= "DINF%2i%2i%2i%2i%2i%2i%2i";

#if 0
const char*	 kMsgCNoop 			= "CNOP";
const char*	 kMsgCClose 		= "CBYE";
const char*	 kMsgCClipboard 	= "CCLP%1i%4i";
const char*	 kMsgCScreenSaver 	= "CSEC%1i";
const char*	 kMsgCResetOptions	= "CROP";
const char*	 kMsgCInfoAck		= "CIAK";
const char*	 kMsgDKeyDown1_0	= "DKDN%2i%2i";
const char*	 kMsgDKeyRepeat1_0	= "DKRP%2i%2i%2i";
const char*	 kMsgDKeyUp1_0		= "DKUP%2i%2i";
const char*	 kMsgDMouseRelMove	= "DMRM%2i%2i";
const char*	 kMsgDMouseWheel	= "DMWM%2i%2i";
const char*	 kMsgDMouseWheel1_0	= "DMWM%2i";
const char*	 kMsgDClipboard		= "DCLP%1i%4i%s";
const char*	 kMsgDSetOptions	= "DSOP%4I";
const char*	 kMsgEIncompatible	= "EICV%2i%2i";
const char*	 kMsgEBusy 			= "EBSY";
const char*	 kMsgEUnknown		= "EUNK";
const char*	 kMsgEBad			= "EBAD";
#endif

#define KEEPALIVE_PERIOD 2


//not the best place for it, but im lazy
NSInteger printableCharacters[] = {32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,128,129,130,131,132,134,135,137,139,140,141,142,143,144,145,146,147,148,149,151,153,155,156,157,158,161,162,163,164,165,166,167,169,170,171,172,174,175,176,177,178,179,181,182,183,184,185,186,187,188,189,190,191,197,198,199,208,215,216,222,223,229,230,231,240,247,248,254};

static void socketDataCallback (CFSocketRef s,
								CFSocketCallBackType callbackType,
								CFDataRef address,
								const void *data,
								void *info)
{
	SynergyClient * synergyClient = (__bridge SynergyClient *) info;
    if (callbackType == kCFSocketReadCallBack) {
		[synergyClient handleSocketCallback];
    }
}

@implementation SynergyClient

@synthesize delegate;
@synthesize connectionError;

-(void) initSocketStateMachine {	
	readPos = 0;
	bytesToRead = 4;
	bytesToSkip = 0;
	socketState = SOCKET_W4_HEADER;
}

-(void) handleSocketCallback {
	
	int bytes_read = read(socketFD, message+readPos, bytesToRead);
	if (bytes_read <= 0){
		NSLog(@"-[SynergyClient handleSocketCallback] Connection broken!");
		[self stopConnection];
		[delegate remoteDisconnected];
		return;
	}
	readPos += bytes_read;
	bytesToRead -= bytes_read;

	if (bytesToRead > 0) {
		return;
	}
	switch (socketState){
		case SOCKET_W4_HEADER:
			bytesToRead = ntohl( *((uint32_t *) message));
			// handle overrun
			if (bytesToRead < MAX_MESSAGE) {
				socketState = SOCKET_W4_DATA;
			} else {
				bytesToSkip = bytesToRead - MAX_MESSAGE;
				bytesToRead = MAX_MESSAGE;
				socketState = SOCKET_W4_SKIP;
			}
			readPos = 0;
			break;
		case SOCKET_W4_DATA:
			// add \0 and handle packet
			message[readPos] = 0;
			[self handleMessageWithLen:readPos];
			// reset state machine
			[self initSocketStateMachine];
			break;
		case SOCKET_W4_SKIP:
			if (bytesToSkip >= MAX_MESSAGE) {
				bytesToRead = MAX_MESSAGE;
				bytesToSkip -= MAX_MESSAGE;
				readPos = 0;
			} else if (bytesToSkip) {
				bytesToRead = bytesToSkip;
				bytesToSkip = 0;
				readPos = 0;
			} else {
				// reset state machine
				[self initSocketStateMachine];
			}
			break;
	}
}


-(id) init {
	
	// init socket statemachine
	[self initSocketStateMachine];
	
	// init synergy statemachine
	clientState = STATE_NOT_CONNECTED;

	// mouse state
	mouseShown = NO;	

	// (try to) ignore SIGPIPE
    struct sigaction act;
    act.sa_handler = SIG_IGN;
    sigemptyset (&act.sa_mask);
    act.sa_flags = 0;
    sigaction (SIGPIPE, &act, NULL);
	
	// load libActivator
    /*
	dlopen("/usr/lib/libactivator.dylib", RTLD_LAZY);
	activator = [objc_getClass("LAActivator") sharedInstance];
	if (activator && [[NSUserDefaults standardUserDefaults] boolForKey:keyActivatorDefautsApplied] == NO) {
		 LAEvent *event = [[[objc_getClass("LAEvent") alloc] initWithName:@"ch.ringwald.synergymouse.right" mode:[activator currentEventMode]] autorelease];
		[activator assignEvent:event toListenerWithName:@"libactivator.system.homebutton"];
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:keyActivatorDefautsApplied];
	}
     */
	return self;
}

-(void) hexdump:(uint16_t) len{
	printf("Data: ");
	int i; for (i=0; i<len ; i++) printf("%02x ", ((uint8_t *) message)[i]);
	printf("\n");
}


-(int) writeMessage:(const char *) format, ...  {
	
	int pos = 4;
	int value;
	char * string;
	int len;
	
	va_list argptr;
    va_start(argptr, format);
	
	while (*format){
		if (*format == '%'){
			++format;
			// get len info
			len = 0;
			if (*format >= '0' && *format <= '9'){
				len = *format++ - '0';
			}
			switch (*format) {
				case 'i':
					value = va_arg(argptr, int);
					switch (len){
						case 1:
							message[pos++] = value;
							break;
						case 2:
							message[pos++] = value >>  8;
							message[pos++] = value;
							break;
						case 4:
							message[pos++] = value >> 24;
							message[pos++] = value >> 16;
							message[pos++] = value >>  8;
							message[pos++] = value;
							break;
						default:
							break;
					}
					break;
				case 's':
					string = va_arg(argptr, char *);
					len = strlen(string);
					message[pos++] = len >> 24;
					message[pos++] = len >> 16;
					message[pos++] = len >>  8;
					message[pos++] = len;
					memcpy( message + pos, string, len);
					pos += len;
					break;
					
				default:
					break;
			}
			++format;
		} else {
			message[pos++] = *format++;
		}
	}
	
    va_end(argptr);
	
	len = pos - 4;
	message[0] = len >> 24;
	message[1] = len >> 16;
	message[2] = len >>  8;
	message[3] = len;
	
	write(socketFD, message, pos);
	
	return pos;
}

-(int) parseMessage:(const char *) format, ...  {
	
	int pos = 0;
	int value;
	int len;
	int i;
	int * data;
	
	va_list argptr;
    va_start(argptr, format);
	
	while (*format){
		if (*format == '%'){
			++format;
			// get len info
			len = 0;
			if (*format >= '0' && *format <= '9'){
				len = *format++ - '0';
			}
			switch (*format) {
				case 'i':
					/// value = va_arg(argptr, int *);
					value = 0;
					for (i=0;i<len;i++){
						value = (value << 8) | message[pos++];
					}
					data = va_arg(argptr, int *);
					*data = value;
					break;
				case 's':
					// skip strings
					len = 0;
					for (i=0;i<4;i++){
						len = (len << 8) | message[pos++];
					}
					pos += len;
					break;
					
				default:
					break;
			}
			++format;
		} else {
			// matcher
			if (message[pos++] != *format++) {
				return -1;
			}
		}
	}
    va_end(argptr);
	return 0;
}

-(BOOL) openConnection:(NSString *) remote {
	
	connectionError = @"Unknown error - sorry";

	// init state machine
	[self initSocketStateMachine];
	
	// cretate TCP socket
    struct protoent* tcp = getprotobyname("tcp");
	socketFD = socket(PF_INET, SOCK_STREAM, tcp->p_proto);
	if(socketFD == -1){
		connectionError = @"Cannot create local socket";
		return NO; // cannot create local socket
	}
	
	// set NO_SIGPIPE
	int noSigPipe=1;
	setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
	
	// set non-blocking
	
    // .. to localhost synergy port
	struct sockaddr_in synergy_server_address;
	synergy_server_address.sin_family = AF_INET;
	synergy_server_address.sin_port = htons(24800);
	if (!remote || [remote length] == 0) return NO;
	struct hostent* remotehost = gethostbyname([remote cStringUsingEncoding:NSASCIIStringEncoding]);
	if(!remotehost){
		connectionError = @"Could not resolve server address";
		return NO;	// cannot resolve server address
	}
		
	// Set non-blocking 
	long arg;
	if( (arg = fcntl(socketFD, F_GETFL, NULL)) < 0) { 
		connectionError = @"Failed to set socket options - O_NONBLOCK-1";
		return NO; 
	} 
	arg |= O_NONBLOCK; 
	if( fcntl(socketFD, F_SETFL, arg) < 0) { 
		connectionError = @"Failed to set socket options - O_NONBLOCK-2";
		return NO;; 
	} 

	char* addr = remotehost->h_addr_list[0];
	memcpy(&synergy_server_address.sin_addr.s_addr, addr, sizeof(struct in_addr));


	// Trying to connect with timeout 
	socklen_t lon; 
	fd_set myset; 
	struct timeval tv; 
	int valopt; 

	int res = connect(socketFD, (struct sockaddr*)&synergy_server_address, sizeof synergy_server_address); 
	if (res < 0) { 
		if (errno == EINPROGRESS) { 
			// fprintf(stderr, "EINPROGRESS in connect() - selecting\n"); 
			do { 
				tv.tv_sec = 5; 
				tv.tv_usec = 0; 
				FD_ZERO(&myset); 
				FD_SET(socketFD, &myset); 
				res = select(socketFD+1, NULL, &myset, NULL, &tv); 
				if (res < 0 && errno != EINTR) { 
					connectionError = [[NSString alloc] initWithFormat:@"%s (%d)", strerror(errno), errno];
					return NO;
				} 
				else if (res > 0) { 
					// Socket selected for write 
					lon = sizeof(int); 
					if (getsockopt(socketFD, SOL_SOCKET, SO_ERROR, (void*)(&valopt), &lon) < 0) { 
						connectionError = [[NSString alloc] initWithFormat:@"%s (%d)", strerror(errno), errno];
						return NO;
					} 
					// Check the value returned... 
					if (valopt) { 
						connectionError = [[NSString alloc] initWithFormat:@"%s (%d)", strerror(valopt), errno];
						return NO;
					} 
					break; 
				} 
				else { 
					connectionError = @"Timeout";
					return NO;
				} 
			} while (1); 
		} 
		else { 
			connectionError = [[NSString alloc] initWithFormat:@"%s (%d)", strerror(errno), errno];
			return NO;
		} 
	}
	
	// Set to blocking mode again... 
	if( (arg = fcntl(socketFD, F_GETFL, NULL)) < 0) { 
		connectionError = @"Failed to set socket options - O_NONBLOCK-3";
		return NO; 
	} 
	arg &= (~O_NONBLOCK); 
	if( fcntl(socketFD, F_SETFL, arg) < 0) { 
		connectionError = @"Failed to set socket options - O_NONBLOCK-4";
		return NO; 
	} 
	
	// === add socket to main Cocoa run loop ===
	
	// store reference to us in socket context
	CFSocketContext socketContext;
	bzero(&socketContext, sizeof(CFSocketContext));
	socketContext.info = (__bridge void *)(self);
	
	// create CFSocket from file descriptor
	CFSocketRef cfSocket = CFSocketCreateWithNative (kCFAllocatorDefault,
													 socketFD,
													 kCFSocketReadCallBack,
													 socketDataCallback,
													 &socketContext);
    
	// create run loop source
	CFRunLoopSourceRef socketRunLoop = CFSocketCreateRunLoopSource ( kCFAllocatorDefault, cfSocket, 0);
	CFRelease(cfSocket);
	
    // add to run loop
	CFRunLoopAddSource( CFRunLoopGetMain(), socketRunLoop, kCFRunLoopDefaultMode);
	CFRelease(socketRunLoop);
	
	// I hope that is all
	return YES;		// connection ok
}	

- (void) activateMouse {
	if (!mouseShown) {
		//mouseOpen();
		NSLog(@"Connection to mouse opened");
		//mouseShown = YES;
	}
	
}

- (void) deactivateMouse {
	if (mouseShown) {
		//mouseClose();
		NSLog(@"Connection to mouse closed");
		//mouseShown = NO;
	}
}

- (void) sendPeriodicAliveMessage {

	if (clientState == STATE_CONNECTED || clientState == STATE_LIVE) {
		// NSLog(@"Keep alive send");
		[self writeMessage:kMsgCKeepAlive];

		// set new timer for next keep alive message
		[self performSelector:@selector(sendPeriodicAliveMessage) withObject:nil afterDelay:KEEPALIVE_PERIOD];
	}
}

//saiyen
//send a screensaver ended message to cause the server to re-query screen resolution.
- (void) sendResetOptionsMessage {
	if (clientState == STATE_CONNECTED || clientState == STATE_LIVE) {
        [self deactivateMouse];
        [self writeMessage:kMsgDInfo, 0, 0, screenWidth, screenHeight, screenWidth/2, screenHeight/2];
        [self activateMouse];
	}
}
//saiyen

- (void) handleMessageWithLen:(uint16_t)len {
	
	static int mouseButton = 0;
	static float mouseX = 0;
	static float mouseY = 0;
	static int shiftDown = 0;
	static int ctrlDown = 0;
	// int ok;
	
	// NSLog(@"Message: '%s'\n", message);
	// [self hexdump:len];
	
	if (strncmp("Synergy", (char*)message, 7) == 0){
		NSString * name = [self clientName];
		if ( name == nil || [name length] == 0){
			name = [self hostName];
		}
		[self writeMessage:kMsgHelloBack, 1, 3, [name cStringUsingEncoding:NSASCIIStringEncoding]];
	}
	if (strncmp(kMsgQInfo, (char*)message, 4) == 0){
		// connected
		clientState = STATE_CONNECTED;
		[delegate connectionStateChanged];
		[self writeMessage:kMsgDInfo, 0, 0, screenWidth, screenHeight, screenWidth/2, screenHeight/2];
		[self sendPeriodicAliveMessage];
	}
#if 0
	if (strncmp(kMsgCKeepAlive, (char*)message, 4) == 0){
		// NSLog(@"Keep alive received");
		[self writeMessage:kMsgCKeepAlive];
	}
#endif
	if (strncmp(kMsgDKeyDown, (char*)message, 4) == 0){
		int a1, a2, a3;
		[self parseMessage:kMsgDKeyDown, &a1, &a2, &a3];
        //NSLog(@"kMsgDKeyDown ID %04x, MASK %04x, BUTTON %04x\n", a1, a2, a3);
        //NSLog(@"DOWN %u, %u, %u\n\n", a1, a2, a3);
        //Do some checking that function keys are translated properly
        //if its not a printable character and not a supported function key dont emulate it
        //here are the function keys we're going to support.
        /*
        NSUpArrowFunctionKey  61266
        NSDownArrowFunctionKey  61268
        NSLeftArrowFunctionKey  61265
        NSRightArrowFunctionKey  61267
        NSBackspaceKey  61192
        NSCarriageReturnKey 61197
        NSDeleteKey
         */
        switch (a1) {
            case 61266:
                a1 = NSUpArrowFunctionKey;
                break;
            case 61268:
                a1 = NSDownArrowFunctionKey;
                break;
            case 61265:
                a1 = NSLeftArrowFunctionKey;
                break;
            case 61267:
                a1 = NSRightArrowFunctionKey;
                break;
            case 61192:
                a1 = NSBackspaceKey;
                break;
            case 61197:
                a1 = NSCarriageReturnKey;
                break;
            default:{
                //cant call contains with an int, run through the array, if found, break, else return
                BOOL found = NO;
                int len=sizeof(printableCharacters)/sizeof(int);
                for (int i=0;i<len; i++){
                    if(a1 == printableCharacters[i]){
                        found = YES;
                        break;
                    }
                }
                if(!found){
                    return;
                }
            }
                break;
        }
        //NSLog(@"DOWN %u, %u, %u", a1, a2, a3);
        //Shift+apple+H = home key
        //HWButtonHome
        if(a1 == 72 && a3 == 5 &&  [self homeButtonHotkey]){
            hid_inject_button_down(HWButtonHome);
            hid_inject_button_up(HWButtonHome);
            return;
        }
        
        hid_inject_key_down(a1, 0);
		// NSLog(@"CtrlActive = %u, ShiftActive = %u\n", ctrlDown, shiftDown);
	}		
	if (strncmp(kMsgDKeyUp, (char*)message, 4) == 0){
		int a1, a2, a3;
		[self parseMessage:kMsgDKeyUp, &a1, &a2, &a3];
		//NSLog(@"kMsgDKeyUp ID %04x, MASK %04x, BUTTON %04x\n", a1, a2, a3);
        //NSLog(@"UP %u, %u, %u\n", a1, a2, a3);
        
        //a1 is always 0, problem with parse message? or by design?
        hid_inject_key_up(a1);
		// NSLog(@"CtrlActive = %u, ShiftActive = %u\n", ctrlDown, shiftDown);
	}		
	if (strncmp(kMsgDMouseMove, (char*)message, 4) == 0){
		int x, y;
		[self parseMessage:kMsgDMouseMove, &x, &y];
		mouseX = x; mouseY = y;
        hid_inject_mouse_abs_move(mouseButton, mouseX, mouseY);
        //mouseSendEvent( mouseX, mouseY, mouseButton);
        NSLog(@"Mouse button %u at %f,%f\n", mouseButton, mouseX, mouseY);
	}
	if (strncmp(kMsgDMouseDown, (char*)message, 4) == 0){

		int button;
		[self parseMessage:kMsgDMouseDown, &button];
		
		// simulate middle/right mouse button
		// -- CTRL + mouse = right click
		if (button == 1 && shiftDown) {
			button = 2;
		}
		if (button == 1 && ctrlDown) {
			button = 3;
		}
		       
        // right-click sends home-button through hid-support
        if (button == 3) {
            hid_inject_button_down(HWButtonHome);
            hid_inject_button_up(HWButtonHome);
        }
      
		// only send left clicks to MouseSupport
		if (button == 1) {
			mouseButton = 1;
		} else {
			mouseButton = 0;
		}
        
        
        hid_inject_mouse_abs_move(mouseButton, mouseX, mouseY);
		//mouseSendEvent( mouseX, mouseY, mouseButton);
		NSLog(@"Mouse down %u at %f,%f\n", button, mouseX, mouseY);
	}
	if (strncmp(kMsgDMouseUp, (char*)message, 4) == 0){
		int i;
		[self parseMessage:kMsgDMouseUp, &i];
		mouseButton = 0;
        hid_inject_mouse_abs_move(mouseButton, mouseX, mouseY);
		//mouseSendEvent( mouseX, mouseY, mouseButton);
		NSLog(@"Mouse up %u at %f,%f\n", i, mouseX, mouseY);
	}
	if (strncmp(kMsgCEnter, (char*)message, 4) == 0){
		// connected
		clientState = STATE_LIVE;
		[delegate connectionStateChanged];

		// reset mouse modifiers
		ctrlDown = shiftDown = 0;
		[self activateMouse];
	}	
	if (strncmp(kMsgCLeave, (char*)message, 4) == 0){
		// connected
		clientState = STATE_CONNECTED;
		[delegate connectionStateChanged];
		[self deactivateMouse];
	}	
}

-(void) startOpeningConnection {

	@autoreleasepool {
	// NSLog(@"Start Connection");
		if (clientState == STATE_NOT_CONNECTED){
			// start connection
			clientState = STATE_CONNECTING;
			// NSLog(@"set clientState to connecting..");
			[delegate performSelectorOnMainThread:@selector(connectionStateChanged) withObject:nil waitUntilDone:NO];
			BOOL ok = [self openConnection:[self serverAddress]];
			if (!ok){
				clientState = STATE_NOT_CONNECTED;
				[delegate performSelectorOnMainThread:@selector(connectionFailed) withObject:nil waitUntilDone:NO];
			}
			[delegate performSelectorOnMainThread:@selector(connectionStateChanged) withObject:nil waitUntilDone:NO];
		}
	}
}

-(void) stopConnection {
	// NSLog(@"Stop Connection");
	if (clientState != STATE_NOT_CONNECTED){
		[self deactivateMouse];
		close(socketFD);
		clientState = STATE_NOT_CONNECTED;
	}
	[delegate connectionStateChanged];
}
-(NSString *) connectionStatus{
	switch (clientState) {
		case STATE_NOT_CONNECTED:
			return @"Not connected";
		case STATE_CONNECTING:
			return @"Connecting...";
		case STATE_CONNECTED:
			return @"Connected";
		case STATE_LIVE:
			return @"Live!";
		default:
			return @"Don't know!";
	}
}

-(CLIENT_STATE) clientState {
	return clientState;
}

-(BOOL) isConnecting{
	return clientState == STATE_CONNECTING;
}

static char name[80];
-(NSString *) hostName{
	gethostname(name, 80);
	return [NSString stringWithCString:name encoding:NSASCIIStringEncoding];
}

-(void) setEnabled:(BOOL)enabled{
	_enabled = enabled;
}
-(BOOL) enabled{
	return _enabled;
}
-(BOOL) keyboardSupportInstalled{
	return YES;
}

-(void) setScreenWidth:(int)width andHeight:(int)height{
	screenWidth  = width;
	screenHeight = height;
}

#pragma mark Preferences
-(NSString *) serverAddress {
	return [[NSUserDefaults standardUserDefaults] stringForKey:keyServerAddress];
}
-(void) setServerAddress:(NSString *) serverAddress{
	[[NSUserDefaults standardUserDefaults] setObject:serverAddress forKey:keyServerAddress];
}
-(NSString *) clientName{
	return [[NSUserDefaults standardUserDefaults] stringForKey:keyClientName];
}
-(void) setClientName:(NSString *) clientName{
	[[NSUserDefaults standardUserDefaults] setObject:clientName forKey:keyClientName];
}
-(BOOL) homeButtonHotkey{
	return [[NSUserDefaults standardUserDefaults] boolForKey:keyHomeButtonHotkey];
}
-(void) setHomeButtonHotKey:(BOOL) homeButtonHotKey{
	[[NSUserDefaults standardUserDefaults] setBool:homeButtonHotKey forKey:keyHomeButtonHotkey];
}
@end
