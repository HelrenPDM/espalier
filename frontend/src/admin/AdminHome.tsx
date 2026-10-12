import { useTranslation } from "react-i18next";
import { useSession } from "../auth/SessionProvider";
import { PasskeyNotice } from "./passkeyGate";
import { usePasskeyRequired } from "./passkeyRequired";

/**
 * The start page `/admin`. An admin without a passkey sees the passkey
 * notice here as well, while the gate is closed.
 */
export function AdminHome() {
  const { t } = useTranslation();
  const { roles } = useSession();
  const passkeyRequired = usePasskeyRequired();

  return (
    <section className="max-w-2xl">
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.title")}
      </h1>
      <p className="mt-4 text-gray-700 dark:text-gray-300">
        {t("admin.intro")}
      </p>
      {passkeyRequired && roles.includes("admin") && (
        <div className="mt-8">
          <PasskeyNotice level={2} />
        </div>
      )}
    </section>
  );
}
