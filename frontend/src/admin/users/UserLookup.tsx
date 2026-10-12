import { useId, useState, type FormEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useUserLookup, type AdminUser } from "../../api/admin/users";
import { ApiError } from "../../api/errors";
import { Button, TextField } from "../../app/forms";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useAdminErrorText } from "../adminErrors";

/**
 * The lookup of one user by the exact e-mail address (task 0015, steps 12
 * and 15) through `POST /api/admin/user-lookups`, which takes the address
 * in its body. `children` renders the user that the lookup found; the
 * users page shows it with its actions, the roles page with its grants.
 * Every change on that user refreshes the lookup with the list.
 */
export function UserLookup({
  children,
}: {
  children: (user: AdminUser, headingId: string) => ReactNode;
}) {
  const { t } = useTranslation();
  const errorText = useAdminErrorText();
  const headingId = useId();
  const resultId = useId();
  const [value, setValue] = useState("");
  const [email, setEmail] = useState<string | null>(null);
  const lookup = useUserLookup(email);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const trimmed = value.trim();
    if (trimmed === "") return;
    if (trimmed === email) void lookup.refetch();
    else setEmail(trimmed);
  };

  let result: ReactNode = null;
  if (email !== null) {
    if (lookup.isPending) {
      result = <LoadingStatus text={t("admin.users.lookup.loading")} />;
    } else if (lookup.isError) {
      result =
        lookup.error instanceof ApiError && lookup.error.status === 404 ? (
          <p role="status" className="text-gray-700 dark:text-gray-300">
            {t("admin.users.lookup.notFound")}
          </p>
        ) : (
          <p role="alert" className="text-red-700 dark:text-red-300">
            {errorText(lookup.error)}
          </p>
        );
    } else {
      result = (
        <div className="space-y-3">
          <h3 id={resultId} className="text-lg font-semibold">
            {t("admin.users.lookup.result")}
          </h3>
          {children(lookup.data, resultId)}
        </div>
      );
    }
  }

  return (
    <section aria-labelledby={headingId} className="mt-10 space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.users.lookup.title")}
      </h2>
      <form onSubmit={submit} className="max-w-md space-y-3">
        <TextField
          label={t("admin.users.lookup.email")}
          hint={t("admin.users.lookup.hint")}
          type="email"
          name="lookup-email"
          autoComplete="off"
          maxLength={254}
          required
          value={value}
          onChange={(event) => setValue(event.target.value)}
        />
        <Button type="submit" disabled={lookup.isFetching}>
          {t("admin.users.lookup.submit")}
        </Button>
      </form>
      {result}
    </section>
  );
}
