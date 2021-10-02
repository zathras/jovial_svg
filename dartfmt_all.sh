# Run dartfmt on everything of interest, without distraction from
# generated code.
dart format lib lib/src example/lib demo/lib
# was dartfmt -w lib/*.dart lib/src/*.dart example/lib/*.dart demo/lib/*.dart
