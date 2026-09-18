# OMMDB access request (draft for Aziz to send)

Dataset page: https://scazlab.yale.edu/ommdb-dataset
Paper: Matheus, Mamantov, Vázquez, Scassellati, "Deep Breathing Phase
Classification with a Social Robot for Mental Health", ICMI 2023,
https://doi.org/10.1145/3577190.3614173

Contacts listed on the dataset page: kayla.matheus@yale.edu,
ellie.mamantov@yale.edu, marynel.vazquez@yale.edu, brian.scassellati@yale.edu.
Send to Kayla Matheus and Ellie Mamantov (first authors), cc the two PIs.

Before sending, decide the one thing the reply will hinge on: we are a
company, not a lab. Most university dataset agreements permit research use
and forbid commercial use. The draft says so plainly and asks what terms
would allow it; do not download anything until that is answered in writing.

---

Subject: OMMDB access for a breathing-measurement study (808, Lock Out Inc.)

Hi Kayla and Ellie,

I read your ICMI 2023 paper on deep breathing phase classification and the
OMMDB dataset, and I would like to ask about access.

I am a cofounder of 808, an iPhone and Apple Watch app that measures a
meditation session from body signals: stillness and breathing rate from
Watch motion, shown to the user after the session. We are building a
version for people without a Watch that reads the same two signals from
the front camera of a phone propped in front of them. Our engine estimates
breathing rate from torso motion at 10 frames per second, which is the
rate your dataset is sampled at, from a head-and-shoulders framing very
close to Ommie's camera view.

What we lack is ground truth from people other than ourselves. Our
validation so far is a handful of our own sits against the Watch, which is
itself an estimate. Your 280 sessions with a respiration belt and video
from a comparable framing would let us measure our estimator's accuracy on
deliberate slow breathing across 47 people, and its false-positive rate,
which no public dataset we have found covers.

To be direct about who is asking: 808 is a commercial product. We would
use the data only to evaluate and tune our estimator offline, never
redistribute it, never ship any frame or derived data from it, and we
would be glad to cite the paper and share what we find. If your data-use
terms permit research use only, I would like to know whether an evaluation
of this kind fits, or what terms would.

Happy to sign whatever agreement you use.

Thank you for making the dataset available.

Aziz Mahmud
Cofounder, 808 (Lock Out Inc.)
meditate808.com
