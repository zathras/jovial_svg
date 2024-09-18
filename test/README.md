# Regression Tests

This directory contains regression tests for the library.

Please be aware that it's not at all suprising if the tests fail on your
computer.  Many of them rely on rendering an asset, and then comparing the
result with a previous rendering.  Flutter does __not__ guarantee consistent,
pixel-identical rendering across platforms, or across versions of Flutter on
the same platform.

A good way to use these is to first run the tests before making a change.  If
you get test failures, it's probably for one of the reasons given above, so
it should be safe to run the tests in the mode that re-writes any reference
images that don't match.  See `rewriteAllFailedTests` in `test_main.dart`.
And yes, it's a little inconvenient to change source to do this.  That's
intentional.

Once you've generated reference images for your platform/flutter version,
then you can try making the change you want to the library.  After your change,
the tests should pass (unless you just fixed a bug that caused one of the
reference  images to be wrong!).

The reference images in the repo were generated on Linux, using the action
https://github.com/zathras/jovial_svg/actions/workflows/test_rewrite.yaml .
When the underlying platform changes in a way that changes the rendering, I 
check that the results look the same, by visual inspection.
