---
title: Building a prompt
position: 1
---

:::text{provenance=invented}
A [[term:prompt]] gives better results when it names four parts: the task, the context, the format and a constraint.
:::

:::explanation{provenance=invented}
The assistant knows only what the prompt and the conversation contain. Everything inside its [[term:context-window|context window]] can shape the answer, and everything outside it cannot. When the prompt names all four parts, the assistant has less to guess.
:::

:::example{provenance=invented}
A prompt for a notice about a moved meeting can name the four parts like this.

- **Task:** Write a notice to my team that our weekly meeting moves from Tuesday to Thursday.
- **Context:** The team has eight members, and the meeting keeps its time and its room.
- **Format:** Three sentences in plain language, without a subject line.
- **Constraint:** Do not invent reasons for the change.
:::

:::callout{provenance=invented}
Check the input rules of your organization before you paste a document into a prompt.
:::
