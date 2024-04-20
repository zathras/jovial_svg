# Run dartfmt on everything of interest, without distraction from
# generated code.
dart format .
dart run jovial_svg:avd_to_si
dart run jovial_svg:svg_to_si
echo ""
echo "***  Has CHANGELOG.md been updated?  ***"
echo "Checked for warn before all print calls?"
echo ""
printf "          (Press return.)  "
read x
flutter pub publish
