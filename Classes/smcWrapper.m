/*
 *	FanControl
 *
 *	Copyright (c) 2006-2012 Hendrik Holtmann
 *  Portions Copyright (c) 2013 Michael Wilber
 *
 *	smcWrapper.m - MacBook(Pro) FanControl application
 *
 *	This program is free software; you can redistribute it and/or modify
 *	it under the terms of the GNU General Public License as published by
 *	the Free Software Foundation; either version 2 of the License, or
 *	(at your option) any later version.
 *
 *	This program is distributed in the hope that it will be useful,
 *	but WITHOUT ANY WARRANTY; without even the implied warranty of
 *	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *	GNU General Public License for more details.
 *
 *	You should have received a copy of the GNU General Public License
 *	along with this program; if not, write to the Free Software
 *	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import "smcWrapper.h"
#import <CommonCrypto/CommonDigest.h>

static NSArray *allSensors = nil;


@implementation smcWrapper
	io_connect_t conn;

+(void)init{
	SMCOpen(&conn);
    allSensors = [[NSArray alloc] initWithObjects:@"TC0D",@"TC0H",@"TC0F",@"TCAH",@"TCBH",@"TC0P",nil];
}
+(void)cleanUp{
    SMCClose(conn);
}

+(float) get_maintemp{
	float c_temp;
    
    SMCVal_t      val;
    NSString *sensor = [[NSUserDefaults standardUserDefaults] objectForKey:@"TSensor"];
    SMCReadKey2((char*)[sensor UTF8String], &val,conn);
    c_temp= ((val.bytes[0] * 256 + val.bytes[1]) >> 2)/64;
    
    if (c_temp<=0) {
        for (NSString *sensor in allSensors) {
                SMCReadKey2((char*)[sensor UTF8String], &val,conn);
                c_temp= ((val.bytes[0] * 256 + val.bytes[1]) >> 2)/64;
                if (c_temp>0) {
                    [[NSUserDefaults standardUserDefaults] setObject:sensor forKey:@"TSensor"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    break;
                }
        }
    }


	return c_temp;
}


//temperature-readout for MacPro contributed by Victor Boyer
+(float) get_mptemp{
    UInt32Char_t  keyA;
    UInt32Char_t  keyB;
    SMCVal_t      valA;
    SMCVal_t      valB;
   // kern_return_t resultA;
   // kern_return_t resultB;
    sprintf(keyA, "TCAH");
	SMCReadKey2(keyA, &valA,conn);
    sprintf(keyB, "TCBH");
	SMCReadKey2(keyB, &valB,conn);
    float c_tempA= ((valA.bytes[0] * 256 + valA.bytes[1]) >> 2)/64.0;
    float c_tempB= ((valB.bytes[0] * 256 + valB.bytes[1]) >> 2)/64.0;
    int i_tempA, i_tempB;
    if (c_tempA < c_tempB)
    {
        i_tempB = round(c_tempB);
        return i_tempB;
    }
    else
    {
        i_tempA = round(c_tempA);
        return i_tempA;
    }
}

+(int) get_fan_rpm:(int)fan_number{
	UInt32Char_t  key;
	SMCVal_t      val;
	//kern_return_t result;
	sprintf(key, "F%dAc", fan_number);
	SMCReadKey2(key, &val,conn);
	int running= _strtof(val.bytes, val.dataSize, 2);
	return running;
}	

+(int) get_fan_num{
//	kern_return_t result;
    SMCVal_t      val;
    int           totalFans;
	SMCReadKey2("FNum", &val,conn);
    totalFans = _strtoul((char *)val.bytes, val.dataSize, 10);
	return totalFans;
}

+(NSString*) get_fan_descr:(int)fan_number{
	UInt32Char_t  key;
	char temp;
	SMCVal_t      val;
	//kern_return_t result;
	NSMutableString *desc;
//	desc=[[NSMutableString alloc] initWithFormat:@"Fan #%d: ",fan_number+1];
	desc=[[[NSMutableString alloc]init] autorelease];
	sprintf(key, "F%dID", fan_number);
	SMCReadKey2(key, &val,conn);
	int i;
	for (i = 0; i < val.dataSize; i++) {
		if ((int)val.bytes[i]>32) {
			temp=(unsigned char)val.bytes[i];
			[desc appendFormat:@"%c",temp];
		}
	}	
	return desc;
}	


+(int) get_min_speed:(int)fan_number{
	UInt32Char_t  key;
	SMCVal_t      val;
	//kern_return_t result;
	sprintf(key, "F%dMn", fan_number);
	SMCReadKey2(key, &val,conn);
	int min= _strtof(val.bytes, val.dataSize, 2);
	return min;
}	

+(int) get_max_speed:(int)fan_number{
	UInt32Char_t  key;
	SMCVal_t      val;
	//kern_return_t result;
	sprintf(key, "F%dMx", fan_number);
	SMCReadKey2(key, &val,conn);
	int max= _strtof(val.bytes, val.dataSize, 2);
	return max;
}	


+ (BOOL)validateSMC:(NSString*)path
{
    SecStaticCodeRef ref = NULL;
    
    NSURL * url = [NSURL URLWithString:path];
    
    OSStatus status;
    
    // obtain the cert info from the executable
    status = SecStaticCodeCreateWithPath((CFURLRef)url, kSecCSDefaultFlags, &ref);
    
    if (status != noErr) {
        return false;
    }
    
    status = SecStaticCodeCheckValidity(ref, kSecCSDefaultFlags, nil);
    
    if (status != noErr) {
        NSLog(@"Codesign verification failed: Error id = %d",status);
        return false;
    }

    return true;
}

//call smc binary with setuid rights and apply
// The smc binary is given root permissions in FanControl.m with the setRights method.
+(void)setKey_external:(NSString *)key value:(NSString *)value{
	NSString *launchPath = [[NSBundle mainBundle]   pathForResource:@"smc" ofType:@""];
    
    //first check if it's the right binary (security)
    // MW: Disabled smc binary checksum. This should be re-enabled in an official release.
	if (![smcWrapper validateSMC:launchPath]) {
		NSLog(@"smcFanControl: Security Error: smc-binary is not the distributed one");
		return;
	}
    NSArray *argsArray = [NSArray arrayWithObjects: @"-k",key,@"-w",value,nil];
	NSTask *task;
    task = [[NSTask alloc] init];
	[task setLaunchPath: launchPath];
	[task setArguments: argsArray];
	[task launch];
	[task release];
}

@end
