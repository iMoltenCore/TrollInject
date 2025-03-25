@interface DumpDecrypted : NSObject {
	char decryptedAppPathStr[PATH_MAX];
	char *filename;
	char *appDirName;
	char *appDirPath;
}

@property (assign) NSString *appPath;
@property (assign) NSString *docPath;
@property (assign) NSString *appName;
@property (assign) NSString *appVersion;
@property (assign) BOOL crypted;

- (id)initWithPathToBinary:(NSString *)path appName:(NSString *)appName appVersion:(NSString *)appVersion crypted:(BOOL)crypted;
- (void)createIPAFile:(pid_t)pid;
- (NSString *)IPAPath;
@end
