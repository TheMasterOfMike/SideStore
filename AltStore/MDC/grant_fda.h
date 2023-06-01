#ifdef MDC
#pragma once
@import Foundation;

/// Uses CVE-2022-46689 to grant the current app read/write access outside the sandbox.
void grant_fda(void (^_Nonnull completion)(NSError* _Nullable));
bool installdaemon_patch(void);
#endif /* MDC */
