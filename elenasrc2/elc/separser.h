//---------------------------------------------------------------------------
//		E L E N A   P r o j e c t:  ELENA Compiler
//
//		This header contains ELENA Script Engine Parser class declaration.
//
//                                              (C)2005-2016, by Alexei Rakov
//---------------------------------------------------------------------------

#ifndef separserH
#define separserH 1

#include "syntaxtree.h"

#ifdef _WIN32
#include "win32\syslibloader.h"
#endif

namespace _ELENA_
{

class ScriptParser
{
   SysLibraryLoader _library;

   void*(*_InterpretScript)(const char* script);
   void*(*_InterpretFile)(const char* path, int encoding, bool autoDetect);
   void(*_Release)(void* tape);
   int (*_GetStatus)(char* error, int maxLength);

   int _encoding;

public:
   void setOption(ident_t option);

   void parse(path_t filePath, SyntaxTree& tree);

   ScriptParser();
};

} // _ELENA_

#endif // parserH
