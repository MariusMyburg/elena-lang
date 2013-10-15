//---------------------------------------------------------------------------
//		E L E N A   P r o j e c t:  ELENA Common Library
//
//		This file contains Config File class implementation
//                                              (C)2005-2012, by Alexei Rakov
//---------------------------------------------------------------------------

//---------------------------------------------------------------------------
#include "config.h"

using namespace _ELENA_;

// --- IniConfigFile ---

IniConfigFile :: IniConfigFile()
{
}

IniConfigFile :: IniConfigFile(bool allowDuplicates)
   : _settings(allowDuplicates)
{
}

bool IniConfigFile :: load(const _path_t* path, int encoding)
{
   Param line, key, subKey;
   TextFileReader reader(path, encoding, true);

   if (!reader.isOpened())
      return false;

   _text_t buffer[BLOCK_SIZE];
   while (reader.readString(line, buffer)) {
      line.trim('\n');
      line.trim('\r');
      line.trim(' ');

      if (emptystr(line)) continue;

      if (line[0]=='[' && line[line.Length() - 1]==']') {
         if (line.Length() < 3) {
            return false;
         }
         key.copy(line + 1, line.Length() - 2);
         key[line.Length() - 2] = 0;
      }
      else {
         if (emptystr(key)) {
            return false;
         }
         if (line.find('=') != -1) {
            int pos = line.find('=');
            subKey.copy(line, pos);

            _settings.add(key, subKey, line.clone(pos + 1));
         }
         else _settings.add(key, line, (_text_t*)NULL);
      }
   }
   return true;
}

bool IniConfigFile :: save(const _path_t* path, int encoding)
{
   TextFileWriter  writer(path, encoding, true);

   if (!writer.isOpened())
      return false;

   // goes through the section keys
   _Iterator<ConfigSettings::VItem, _MapItem<const _text_t*, ConfigSettings::VItem>, const _text_t*> it = _settings.start();
   while (!it.Eof()) {
      ConfigCategoryIterator cat_it = _settings.getIt(it.key());
      if (!cat_it.Eof()) {
         writer.writeText("[");
         writer.writeText(it.key());
         writer.writeTextNewLine("]");

         while (!cat_it.Eof()) {
            writer.writeText(cat_it.key());
            const _text_t* value = *cat_it;
            if (!emptystr(value)) {
               writer.writeText("=");
               writer.writeTextNewLine(value);
            }
            else writer.writeNewLine();

            cat_it++;
         }
         writer.writeNewLine();
      }
      it++;
   }
   return true;
}

void IniConfigFile :: setSetting(const _text_t* category, const _text_t* key, const _text_t* value)
{
   _settings.add(category, key, StringHelper::clone(value));
}

void IniConfigFile :: setSetting(const _text_t* category, const _text_t* key, int value)
{
   String<_text_t, 15> string;
   string.appendInt(value);

   _settings.add(category, key, string.clone());
}

void IniConfigFile :: setSetting(const _text_t* category, const _text_t* key, size_t value)
{
   String<_text_t, 15> string;
   string.appendInt(value);

   _settings.add(category, key, string.clone());
}

void IniConfigFile :: setSetting(const _text_t* category, const _text_t* key, bool value)
{
   _settings.add(category, key, value ? "-1" : "0");
}

const _text_t* IniConfigFile :: getSetting(const _text_t* category, const _text_t* key, const _text_t* defaultValue)
{
   return _settings.get(category, key, defaultValue);
}

void IniConfigFile :: clear(const _text_t* category, const _text_t* key)
{
	_settings.clear(category, key);
}

void IniConfigFile :: clear(const _text_t* category)
{
   _settings.clear(category);
}

void IniConfigFile :: clear()
{
    _settings.clear();
}
