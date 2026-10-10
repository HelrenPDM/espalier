---
title: Why the same prompt gives different answers
position: 2
---

:::text{provenance=invented}
When you send the same [[term:prompt]] twice, an assistant can answer in two different ways. Both answers can read well and still differ in their facts.
:::

:::explanation{collapsed_on=short provenance=invented}
At each step, the model chooses one of several likely next words. This [[term:sampling]] adds a measured amount of chance, so the wording of an answer, and sometimes its content, changes from one run to the next. The probabilities come from the [[term:training-data|training data]], which the model does not consult again while it writes.
:::

:::example{provenance=invented}
You ask an assistant twice for a one-line summary of the same meeting note. The first answer says that the report is due on Friday, and the second says that it is due next week. Only the meeting note can tell you which answer is right, and you keep the version that you have checked.
:::
