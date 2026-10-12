import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { linkClasses } from "../app/formStyles";
import { useContentLang } from "../player/contentLang";
import { useCurrentPlayer } from "../player/usePlayer";
import { useProgramBase } from "../player/programBase";

/** The link from a station, the glossary or the handbook back to the program page. */
export function BackToProgram() {
  const { t } = useTranslation();
  const programBase = useProgramBase();
  const { program } = useCurrentPlayer();
  const lang = useContentLang();
  return (
    <Link to={`${programBase}/${program.slug}`} className={linkClasses}>
      {t("program.back")} <span lang={lang}>{program.title}</span>
    </Link>
  );
}
