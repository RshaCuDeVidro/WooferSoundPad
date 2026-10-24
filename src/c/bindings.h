#include "raylib.h"
#include "rlgl.h"
#include "woof_audio.h"
#include "woof_http.h"

// From tinyfiledialogs.h: only what the app uses. The full header pulls in
// wchar_t declarations that translate-c can't parse when targeting Windows.
char *tinyfd_openFileDialog(char const *aTitle, char const *aDefaultPathAndOrFile, int aNumOfFilterPatterns,
                            char const *const *aFilterPatterns, char const *aSingleFilterDescription, int aAllowMultipleSelects);
char *tinyfd_selectFolderDialog(char const *aTitle, char const *aDefaultPath);
