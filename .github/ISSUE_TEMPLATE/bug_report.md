---
name: Bug report
about: Bug Report
title: " "
labels: bug
assignees: ''

---

**Some Things to Check**

If your issue is an SVG asset that doesn't parse, or doesn't look the same as when viewed with a browser:
* Have you read the "Supported SVG Profile" and "Goals and Package Evolution" sections of the README?  Cliff notes summary:  Not all SVG files are *expected* to work.
* Have you checked your file to see if it's valid?  See, for example, https://validator.w3.org/
* Have you narrowed it down to a reasonably concise and small SVG file that reproduces the issue?

Before submitting a bug, you *must* look at the SVG file, or have someone who understands SVG look at it for you.  SVG is a very large specificiation, and the README for this project goes into considerable details as to what is -- and isn't -- supported, and why.  Read it.  

Sorry if this comes off as slightly obnoxious, but as the library has become more popular, there has been a decided uptick in "bug" submissions where someone encounters an SVG from somewhere, it doesn't render, and they toss it my way without doing any detective work on their end.  If *that's* what you're after, well, perhaps you should look into commercial vendors who get paid for that kind of support.

**Describe the bug**
A clear and concise description of what the bug is.  If a rendering/parsing bug, be sure to include a copy of a reasonably small SVG that reproduces the issue.

Of course, for non-rendering bugs, standard rules of politeness apply:  You must include code or enough information so that the problem can be easily reproduced.  Generally, this means including a short stand-alone program that shows the problem.

**Additional context**
Add any other context about the problem here.
