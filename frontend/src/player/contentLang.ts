import { useContext } from "react";
import { PlayerContext } from "./usePlayer";

/**
 * The language of the program content (`ProgramView.locale`), which can
 * differ from the UI language. Elements that hold pack text (titles,
 * stems, options, statements, Markdown) carry it as `lang`, so screen
 * readers pronounce them in their own language, while the translated
 * controls keep the language of the document. Outside a player it is
 * `undefined`, and React then renders no `lang`.
 */
export function useContentLang(): string | undefined {
  return useContext(PlayerContext)?.program.locale;
}
