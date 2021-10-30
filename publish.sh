# Run dartfmt on everything of interest, without distraction from
# generated code.
./dartfmt_all.sh
echo ""
echo "***  Has CHANGELOG.md been updated?  ***"
echo ""
printf "          (Press return.)  "
read x
flutter pub publish
