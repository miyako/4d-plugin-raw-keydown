#include <Carbon/Carbon.h>
#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>

// Include the command implementation, not a reconstruction of its callback.
#include "4DPlugin.cpp"

static std::map<PA_Unichar*, size_t> strings;
static std::map<PA_Handle, size_t> handles;
static std::map<PA_Picture, int> pictures;
static bool nullEmpty = false;
static bool returnText = false;
static bool copyInput = false;
static bool callbackError = false;
static CUTF16String expectedName;
static CUTF16String expectedFormat;
static int invocations = 0;

static void require(bool condition, const char* message)
{
    if (!condition)
    {
        std::fprintf(stderr, "ownership regression: %s\n", message);
        std::abort();
    }
}

static PA_Unichar* chars(const char16_t* value)
{
    return const_cast<PA_Unichar*>(reinterpret_cast<const PA_Unichar*>(value));
}

static PA_Unistring makeString(const PA_Unichar* value)
{
    size_t length = 0;
    while (value && value[length]) ++length;
    PA_Unistring result = {};
    result.fLength = static_cast<PA_long32>(length);
    if (length || !nullEmpty)
    {
        result.fString = static_cast<PA_Unichar*>(std::malloc((length + 1) * sizeof(PA_Unichar)));
        require(result.fString != nullptr, "string allocation failed");
        if (length) std::memcpy(result.fString, value, length * sizeof(PA_Unichar));
        result.fString[length] = 0;
        auto pointer = result.fString;
        require(strings.emplace(pointer, length).second, "duplicate allocation");
    }
    return result;
}

static void disposeString(PA_Unistring value)
{
    auto pointer = value.fString;
    if (pointer)
    {
        require(strings.erase(pointer) == 1, "double disposal or borrowed string disposal");
        std::free(pointer);
    }
}

static void expectString(PA_Unistring value, const CUTF16String& expected)
{
    require(value.fLength == expected.size(), "wrong UTF-16 unit length");
    if (value.fString)
    {
        auto pointer = value.fString;
        require(strings.count(pointer) == 1, "string no longer alive");
        require(strings.at(pointer) == expected.size(), "wrong allocation length");
        require(value.fString[value.fLength] == 0, "missing UTF-16 terminator");
        require(CUTF16String(value.fString, value.fLength) == expected, "wrong UTF-16 content");
    }
    else require(expected.empty(), "null nonempty string");
}

static PA_Picture newPicture()
{
    PA_Picture result = std::malloc(1);
    require(result != nullptr, "picture allocation failed");
    pictures[result] = 1;
    return result;
}

static void disposePicture(PA_Picture value)
{
    if (!value) return;
    require(pictures.count(value) == 1 && pictures.at(value) > 0, "invalid picture release");
    if (--pictures[value] == 0)
    {
        pictures.erase(value);
        std::free(value);
    }
}

static void clearVariable(PA_Variable* value)
{
    if (value->fType == eVK_Unistring) disposeString(value->uValue.fString);
    else if (value->fType == eVK_Picture) disposePicture(value->uValue.fPicture);
    else if (value->fType == eVK_ArrayUnicode)
    {
        auto h = value->uValue.fArray.fData;
        if (h)
        {
            require(handles.count(h) == 1, "invalid array handle");
            auto elements = reinterpret_cast<PA_Unistring*>(*h);
            for (PA_long32 i = 0; i <= value->uValue.fArray.fNbElements; ++i)
                disposeString(elements[i]);
            handles.erase(h);
            std::free(*h);
            std::free(h);
        }
    }
    *value = {};
    value->fType = eVK_Undefined;
}

static void setResult(PA_Variable* result, const PA_Unistring* input)
{
    *result = {};
    result->fType = eVK_Undefined;
    if (returnText)
    {
        result->fType = eVK_Unistring;
        result->uValue.fString = makeString(copyInput && input ? input->fString : chars(u"result \u65e5\U0001f600"));
        if (input && input->fString)
            require(result->uValue.fString.fString != input->fString, "return must independently own its text");
    }
}

static void checkCallback(PA_Variable* code, PA_Variable* text, PA_Variable* process)
{
    require(code->fType == eVK_Longint && code->uValue.fLongint == 65, "callback key code changed");
    require(process->fType == eVK_Longint && process->uValue.fLongint == 123, "callback process changed");
    require(text->fType == eVK_Unistring, "callback text type changed");
    expectString(text->uValue.fString, CUTF16String(chars(u"A")));
    ++invocations;
}

static void engine(short selector, EngineBlock* eb)
{
    switch (selector)
    {
        case EX_CREATE_UNISTRING:
            eb->fUniString1 = makeString(reinterpret_cast<PA_Unichar*>(eb->fHandle));
            break;
        case EX_DISPOSE_UNISTRING:
            disposeString(eb->fUniString1);
            break;
        case EX_SET_UNISTRING:
        {
            auto copy = makeString(reinterpret_cast<PA_Unichar*>(eb->fHandle));
            disposeString(eb->fUniString1);
            eb->fUniString1 = copy;
            break;
        }
        case EX_CLEAR_VARIABLE:
            clearVariable(static_cast<PA_Variable*>(eb->fPtr1));
            break;
        case EX_HANDLE_MANAGER:
        {
            auto h = eb->fHandle;
            eb->fError = 0;
            switch (eb->fParam1)
            {
                case 1:
                    h = static_cast<PA_Handle>(std::malloc(sizeof(char*)));
                    require(h != nullptr, "handle allocation failed");
                    *h = static_cast<char*>(std::calloc(1, eb->fParam2 ? eb->fParam2 : 1));
                    require(*h != nullptr, "handle data allocation failed");
                    handles[h] = eb->fParam2;
                    eb->fHandle = h;
                    break;
                case 2:
                    require(handles.erase(h) == 1, "invalid handle disposal");
                    std::free(*h);
                    std::free(h);
                    break;
                case 3:
                    require(handles.count(h) == 1, "invalid handle resize");
                    *h = static_cast<char*>(std::realloc(*h, eb->fParam2 ? eb->fParam2 : 1));
                    require(*h != nullptr, "handle resize failed");
                    handles[h] = eb->fParam2;
                    break;
                case 4:
                    eb->fParam2 = handles.at(h);
                    break;
                case 5:
                    require(handles.count(h) == 1, "invalid handle lock");
                    eb->fParam3 = reinterpret_cast<sLONG_PTR>(*h);
                    break;
                case 6: break;
                default: require(false, "unexpected handle operation");
            }
            break;
        }
        case EX_CALL_BY_PROCID:
        {
            auto params = reinterpret_cast<PA_Variable*>(*eb->fHandle);
            require(eb->fParam1 == 42 && eb->fParam2 == 3, "wrong method invocation");
            checkCallback(&params[1], &params[2], &params[3]);
            setResult(&params[0], &params[2].uValue.fString);
            eb->fError = callbackError ? eER_IncompatibleTypes : 0;
            break;
        }
        case EX_EXECUTE_COMMAND_BY_ID:
        {
            auto args = static_cast<PA_Variable**>(eb->fPtr1);
            PA_Unistring* input = nullptr;
            if (eb->fParam1 == 1007)
            {
                require(eb->fParam2 == 5, "wrong callback argument count");
                expectString(args[0]->uValue.fString, expectedName);
                require(args[1]->fFiller == 1 && args[1]->uValue.fOperation == 3, "lost '*' operation");
                checkCallback(args[2], args[3], args[4]);
                input = &args[3]->uValue.fString;
            }
            else if (eb->fParam1 == 678)
            {
                expectString(args[0]->uValue.fString, expectedName);
                input = &args[0]->uValue.fString;
                disposePicture(args[1]->uValue.fPicture);
                args[1]->uValue.fPicture = newPicture();
            }
            else if (eb->fParam1 == 1002)
            {
                expectString(args[1]->uValue.fString, expectedFormat);
                input = &args[1]->uValue.fString;
            }
            else if (eb->fParam1 == 457)
            {
                args[1]->uValue.fLongint = 12;
                args[2]->uValue.fLongint = 34;
            }
            else if (eb->fParam1 == 679)
            {
                disposePicture(args[1]->uValue.fPicture);
                args[1]->uValue.fPicture = newPicture();
            }
            else require(eb->fParam1 == 988, "unexpected 4D command");
            setResult(static_cast<PA_Variable*>(eb->fPtr2), input);
            eb->fError = callbackError ? eER_IncompatibleTypes : 0;
            break;
        }
        case EX_CREATE_PICTURE:
            // Both null and allocated empty picture representations are exercised.
            eb->fPicture = nullEmpty && !eb->fParam1 ? nullptr : newPicture();
            eb->fError = 0;
            break;
        case EX_DUPLICATE_PICTURE:
        {
            auto picture = eb->fPicture;
            if (eb->fPicture)
            {
                require(pictures.count(picture) == 1, "retaining released picture");
                if (eb->fParam1) eb->fPicture = newPicture();
                else ++pictures[picture];
            }
            break;
        }
        case EX_DISPOSE_PICTURE:
            disposePicture(eb->fPicture);
            break;
        case EX_GET_PICTURE_DATA:
            // No representations; do not guess the ownership of a returned format string.
            eb->fUniString1 = {};
            eb->fError = eER_IncompatibleTypes;
            break;
        case EX_CONVERT_CHARSET_TO_CHARSET:
        {
            require(eb->fParam2 == eVTC_UTF_8 && eb->fParam4 == eVTC_UTF_16, "unexpected charset conversion");
            CFStringRef value = CFStringCreateWithBytes(kCFAllocatorDefault,
                static_cast<const UInt8*>(eb->fPtr1), eb->fParam1, kCFStringEncodingUTF8, false);
            require(value != nullptr, "invalid UTF-8 test fixture");
            CFIndex units = CFStringGetLength(value);
            require(eb->fParam3 >= units * static_cast<CFIndex>(sizeof(PA_Unichar)), "conversion capacity is in bytes");
            CFStringGetCharacters(value, CFRangeMake(0, units), static_cast<UniChar*>(eb->fPtr2));
            eb->fParam3 = units * sizeof(PA_Unichar); // SDK explicitly returns bytes, excluding terminator.
            eb->fError = 0;
            CFRelease(value);
            break;
        }
        default:
            std::fprintf(stderr, "unexpected engine selector: %d\n", selector);
            std::abort();
    }
}

static void checkEmpty()
{
    require(strings.empty(), "unreleased string allocations");
    require(handles.empty(), "unreleased handles");
    require(pictures.empty(), "unreleased picture references");
}

static void callbacks(int id)
{
    Keyboard::userProcessId = 123;
    for (auto name : {u"callback", u"\u65e5", u"\U0001f600", u""})
    {
        expectedName = CUTF16String(chars(name));
        Keyboard::methodName.setUTF16String(expectedName.c_str(), expectedName.size());
        Keyboard::methodId = id;
        for (int i = 0; i < 32; ++i)
        {
            int before = invocations;
            Keyboard::enqueue(65, 'A'); // Never start monitoring or install an input hook.
            Keyboard::callMethod();
            require(invocations == before + (id || !expectedName.empty() ? 1 : 0), "callback dispatch changed");
            require(Keyboard::keycodes.empty() && Keyboard::keychars.empty(), "queue not consumed");
            checkEmpty();
        }
    }
}

static void picturePath()
{
    for (auto path : {u"image.png", u"\u65e5.png", u"\U0001f600.png", u""})
    {
        {
            CPicture picture;
            expectedName = CUTF16String(chars(path));
            C_TEXT text;
            text.setUTF16String(expectedName.c_str(), expectedName.size());
            CUTF8String utf8;
            text.copyUTF8String(&utf8);
            picture.fromFileAtPath(&utf8);
            require(pictures.count(picture.getPicture()) == 1, "loaded picture not retained");
            require(pictures.at(picture.getPicture()) == 1, "loaded picture not independently owned");
        }
        checkEmpty();
    }
}

static void pictureCopy()
{
    for (auto format : {u".png", u"\u65e5", u"\U0001f600", u""})
    {
        {
            CPicture picture;
            expectedFormat = CUTF16String(chars(format));
            C_TEXT text;
            text.setUTF16String(expectedFormat.c_str(), expectedFormat.size());
            CUTF8String utf8;
            text.copyUTF8String(&utf8);
            auto copy = picture.createCopy(reinterpret_cast<const char*>(utf8.c_str()));
            if (copy) require(pictures.at(copy) == 2, "picture return handoff lost a reference");
            PA_DisposePicture(copy);
            unsigned int width = 0, height = 0;
            picture.getSize(&width, &height);
            require(width == 12 && height == 34, "picture properties changed");
            PA_DisposePicture(picture.createGrayScale());
            PA_DisposePicture(picture.createThumbnail(12, 34));
        }
        checkEmpty();
    }
}

static void arrays()
{
    PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
    PA_ResizeArray(&array, 3);
    const char16_t* fixtures[] = {u"", u"ASCII", u"\u65e5", u"\U0001f600"};
    for (int i = 0; i < 4; ++i)
    {
        auto string = PA_CreateUnistring(chars(fixtures[i]));
        PA_SetStringInArray(array, i, &string);
        require(PA_GetStringInArray(array, i).fString == string.fString, "setter must shallow transfer");
    }
    ARRAY_TEXT copy;
    BytePtr params[] = {reinterpret_cast<BytePtr>(&array)};
    copy.fromParamAtIndex(params, 1);
    auto borrowed = PA_GetStringInArray(array, 1);
    auto independent = PA_CreateUnistring(borrowed.fString);
    require(independent.fString != borrowed.fString, "borrowed getter must be copied");
    PA_SetStringInArray(array, 2, &independent);
    auto replacement = PA_CreateUnistring(chars(u"replacement"));
    PA_SetStringInArray(array, 1, &replacement);
    PA_ResizeArray(&array, 0);
    PA_ClearVariable(&array);
    copy.toParamAtIndex(params, 1);
    for (int i = 0; i < 64; ++i)
    {
        auto churn = PA_CreateUnistring(chars(u"allocator churn \u65e5\U0001f600"));
        PA_DisposeUnistring(&churn);
    }
    for (int i = 0; i < 4; ++i)
        expectString(PA_GetStringInArray(array, i), CUTF16String(chars(fixtures[i])));
    copy.toParamAtIndex(params, 1); // Replacement uses fresh independent transfers.
    for (int i = 1; i < 4; ++i)
        for (int j = i + 1; j < 4; ++j)
            require(PA_GetStringInArray(array, i).fString != PA_GetStringInArray(array, j).fString, "shared element allocation");
    for (int index : {-1, 4})
    {
        auto rejected = PA_CreateUnistring(chars(u"rejected"));
        PA_SetStringInArray(array, index, &rejected);
        expectString(rejected, CUTF16String(chars(u"rejected")));
        PA_DisposeUnistring(&rejected);
    }
    auto rejected = PA_CreateUnistring(chars(u"rejected"));
    auto wrong = PA_CreateVariable(eVK_Longint);
    PA_SetStringInArray(wrong, 0, &rejected);
    PA_Variable noData = {};
    noData.fType = eVK_ArrayUnicode;
    PA_SetStringInArray(noData, 0, &rejected);
    expectString(rejected, CUTF16String(chars(u"rejected")));
    PA_DisposeUnistring(&rejected);
    PA_SetStringInArray(array, 0, nullptr);
    expectString(PA_GetStringInArray(array, 0), CUTF16String());
    copy.setSize(1);
    copy.toParamAtIndex(params, 1);
    expectString(PA_GetStringInArray(array, 0), CUTF16String());
    PA_ClearVariable(&array);
    checkEmpty();
}

int main(int argc, char** argv)
{
    require(argc == 5, "expected scenario, empty, result and copy modes");
    gCall4D = engine;
    nullEmpty = std::string(argv[2]) == "null";
    returnText = std::string(argv[3]) != "undefined";
    callbackError = std::string(argv[3]) == "error";
    copyInput = std::string(argv[4]) == "copy";
    std::string scenario(argv[1]);
    if (scenario == "callback-id") callbacks(42);
    else if (scenario == "callback-name") callbacks(0);
    else if (scenario == "path") picturePath();
    else if (scenario == "copy") pictureCopy();
    else if (scenario == "array") arrays();
    else require(false, "unknown scenario");
    checkEmpty();
    std::puts("native ownership: PASS");
}
