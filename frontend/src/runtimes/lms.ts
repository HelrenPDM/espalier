/**
 * The run-time API object that a SCORM 1.2 LMS provides as `window.API`.
 * Every function returns a string: `"true"` or `"false"` for the calls,
 * the value for `LMSGetValue`, and an error code or text for the error
 * functions.
 */
export interface Scorm12Api {
  LMSInitialize(parameter: ""): string;
  LMSFinish(parameter: ""): string;
  LMSGetValue(element: string): string;
  LMSSetValue(element: string, value: string): string;
  LMSCommit(parameter: ""): string;
  LMSGetLastError(): string;
  LMSGetErrorString(errorCode: string): string;
  LMSGetDiagnostic(errorCode: string): string;
}

/**
 * The run-time API object that a SCORM 2004 4th edition LMS provides as
 * `window.API_1484_11`, with the same conventions as `Scorm12Api`.
 */
export interface Scorm2004Api {
  Initialize(parameter: ""): string;
  Terminate(parameter: ""): string;
  GetValue(element: string): string;
  SetValue(element: string, value: string): string;
  Commit(parameter: ""): string;
  GetLastError(): string;
  GetErrorString(errorCode: string): string;
  GetDiagnostic(errorCode: string): string;
}
