import { EyeIcon, EyeSlashIcon } from "@heroicons/react/20/solid";
import {
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
} from "react";
import { useTranslation } from "react-i18next";
import {
  BUTTON_CLASSES,
  FOCUS_RING,
  passwordLength,
  type ButtonVariant,
} from "./formStyles";

/**
 * The form controls of the account pages (README section 9, task 0011 step
 * 15): every input has a visible label, field errors connect through
 * `aria-describedby` and `aria-invalid`, every form has an alert region
 * that exists before an error occurs, and confirmations use a status
 * region.
 */

export function Button({
  variant = "primary",
  type = "button",
  className = "",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant }) {
  return (
    <button
      type={type}
      className={`${BUTTON_CLASSES[variant]} ${className}`}
      {...props}
    />
  );
}

/**
 * The heading of a page or of a wizard step. It has `tabIndex={-1}` and
 * receives focus when it mounts, so focus moves to the new heading after
 * each step change.
 */
export function FocusHeading({
  level = 1,
  children,
  className,
}: {
  level?: 1 | 2;
  children: ReactNode;
  className?: string;
}) {
  const ref = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    ref.current?.focus();
  }, []);
  const Tag = level === 1 ? "h1" : "h2";
  return (
    <Tag
      ref={ref}
      tabIndex={-1}
      className={
        className ??
        (level === 1
          ? "text-2xl font-semibold tracking-tight focus:outline-none"
          : "text-xl font-semibold tracking-tight focus:outline-none")
      }
    >
      {children}
    </Tag>
  );
}

/** The alert region of a form. It is in the DOM before an error occurs. */
export function AlertRegion({ children }: { children?: ReactNode }) {
  return (
    <div
      role="alert"
      className="text-sm font-medium text-red-700 empty:hidden dark:text-red-300"
    >
      {children}
    </div>
  );
}

/** The status region for confirmations such as copied, sent or linked. */
export function StatusRegion({ children }: { children?: ReactNode }) {
  return (
    <div
      role="status"
      className="text-sm font-medium text-green-800 empty:hidden dark:text-green-300"
    >
      {children}
    </div>
  );
}

const INPUT_CLASSES = `mt-1 block w-full rounded-md border border-gray-500 bg-white px-3 py-2 text-gray-900 placeholder:text-gray-500 aria-[invalid=true]:border-red-700 dark:bg-gray-900 dark:text-gray-100 dark:aria-[invalid=true]:border-red-400 ${FOCUS_RING}`;

type FieldProps = {
  label: string;
  /** Messages below the field, connected through `aria-describedby`. */
  errors?: readonly string[];
  /** Guidance below the field, connected through `aria-describedby`. */
  hint?: ReactNode;
  id?: string;
};

function describedBy(...ids: (string | false | undefined)[]) {
  const value = ids.filter(Boolean).join(" ");
  return value === "" ? undefined : value;
}

function FieldErrors({
  id,
  errors,
}: {
  id: string;
  errors: readonly string[];
}) {
  if (errors.length === 0) return null;
  return (
    <ul
      id={id}
      className="mt-1 space-y-1 text-sm text-red-700 dark:text-red-300"
    >
      {errors.map((error) => (
        <li key={error}>{error}</li>
      ))}
    </ul>
  );
}

export function TextField({
  label,
  errors = [],
  hint,
  id,
  ...input
}: FieldProps & Omit<InputHTMLAttributes<HTMLInputElement>, "id">) {
  const generated = useId();
  const inputId = id ?? generated;
  const hintId = `${inputId}-hint`;
  const errorId = `${inputId}-errors`;
  return (
    <div>
      <label
        htmlFor={inputId}
        className="block text-sm font-medium text-gray-900 dark:text-gray-100"
      >
        {label}
      </label>
      <input
        id={inputId}
        className={INPUT_CLASSES}
        aria-invalid={errors.length > 0 ? true : undefined}
        aria-describedby={describedBy(
          hint !== undefined && hintId,
          errors.length > 0 && errorId,
        )}
        {...input}
      />
      {hint !== undefined && (
        <p
          id={hintId}
          className="mt-1 text-sm text-gray-700 dark:text-gray-300"
        >
          {hint}
        </p>
      )}
      <FieldErrors id={errorId} errors={errors} />
    </div>
  );
}

/**
 * A password field (ASVS 6.2.6, 6.2.7, 6.2.9): `type="password"` with a
 * button that reveals the value until it is pressed again or the value is
 * cleared, paste allowed, an `autocomplete` value and no `maxLength`.
 * `counter` shows the code points after NFC normalization against the
 * range of 15 to 128 (README section 6.4).
 */
export function PasswordField({
  label,
  value,
  onChange,
  autoComplete,
  errors = [],
  hint,
  counter = false,
  name,
  required,
}: FieldProps & {
  value: string;
  onChange: (value: string) => void;
  autoComplete: "current-password" | "new-password";
  counter?: boolean;
  name?: string;
  required?: boolean;
}) {
  const { t } = useTranslation();
  const inputId = useId();
  const [revealed, setRevealed] = useState(false);
  const hintId = `${inputId}-hint`;
  const counterId = `${inputId}-counter`;
  const errorId = `${inputId}-errors`;
  if (revealed && value === "") setRevealed(false);

  return (
    <div>
      <label
        htmlFor={inputId}
        className="block text-sm font-medium text-gray-900 dark:text-gray-100"
      >
        {label}
      </label>
      <div className="mt-1 flex gap-2">
        <input
          id={inputId}
          type={revealed ? "text" : "password"}
          name={name}
          value={value}
          required={required}
          autoComplete={autoComplete}
          spellCheck={false}
          autoCapitalize="off"
          onChange={(event) => onChange(event.target.value)}
          className={`${INPUT_CLASSES} mt-0`}
          aria-invalid={errors.length > 0 ? true : undefined}
          aria-describedby={describedBy(
            counter && counterId,
            hint !== undefined && hintId,
            errors.length > 0 && errorId,
          )}
        />
        <button
          type="button"
          aria-pressed={revealed}
          aria-controls={inputId}
          onClick={() => setRevealed((current) => !current)}
          className={`shrink-0 rounded-md border border-gray-500 px-3 text-gray-800 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-gray-800 ${FOCUS_RING}`}
        >
          {revealed ? (
            <EyeSlashIcon aria-hidden="true" className="size-5" />
          ) : (
            <EyeIcon aria-hidden="true" className="size-5" />
          )}
          <span className="sr-only">{t("auth.forms.showPassword")}</span>
        </button>
      </div>
      {counter && (
        <p
          id={counterId}
          className="mt-1 text-sm text-gray-700 dark:text-gray-300"
        >
          {t("account.password.counter", { count: passwordLength(value) })}
        </p>
      )}
      {hint !== undefined && (
        <p
          id={hintId}
          className="mt-1 text-sm text-gray-700 dark:text-gray-300"
        >
          {hint}
        </p>
      )}
      <FieldErrors id={errorId} errors={errors} />
    </div>
  );
}
