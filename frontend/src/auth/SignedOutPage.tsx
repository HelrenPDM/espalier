import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { FocusHeading } from "../app/forms";
import { linkClasses } from "../app/formStyles";

/**
 * `/signed-out`, the `post_logout_redirect_uri` of an RP-initiated logout
 * (README sections 6.7 and 6.12): the provider ended its session too.
 */
export function SignedOutPage() {
  const { t } = useTranslation();
  return (
    <section className="max-w-2xl space-y-4">
      <FocusHeading>{t("auth.signedOut.title")}</FocusHeading>
      <p className="text-gray-700 dark:text-gray-300">
        {t("auth.signedOut.body")}
      </p>
      <p>
        <Link to="/sign-in" className={linkClasses}>
          {t("auth.signedOut.signIn")}
        </Link>
      </p>
    </section>
  );
}
