#import "SZOperationSessionDefaults.h"

#import "../Dialogs/SZDialogPresenter.h"

#if SHICHIZIP_ZS_VARIANT
#import "ShichiZip_ZS-Swift.h"
#else
#import "ShichiZip-Swift.h"
#endif

SZOperationSession* SZMakeDefaultOperationSession(void) {
    SZOperationSession* session = [SZOperationSession new];
    session.passwordRequestHandler = ^BOOL(NSString* title,
        NSString* message,
        NSString* initialValue,
        NSString* _Nullable* _Nullable password) {
        return [SZDialogPresenter promptForPasswordWithTitle:title
                                                     message:message
                                                initialValue:initialValue
                                                    password:password];
    };
    session.choiceRequestHandler = ^NSInteger(SZOperationChoiceRequest* request) {
        return [SZDialogPresenter runChoiceRequest:request];
    };
    session.updateEncryptionRequestHandler = ^SZArchiveUpdateEncryption*(NSString* archivePath, SZEncryptionMethod defaultEncryption) {
        return [SZArchiveUpdateEncryptionDialog runModalForArchive:archivePath defaultEncryption:defaultEncryption];
    };
    return session;
}
