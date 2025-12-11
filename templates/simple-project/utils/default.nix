{ lib }:

{
  # 字符串工具
  strings = {
    # Convert string to camelCase
    camelCase = str:
      let
        parts = lib.splitString "-" str;
        capitalize = part:
          let
            first = lib.substring 0 1 part;
            rest = lib.substring 1 (lib.stringLength part - 1) part;
          in
          lib.toUpper first + lib.toLower rest;
      in
      lib.concatMapStrings (part: capitalize part) parts;
  };
}