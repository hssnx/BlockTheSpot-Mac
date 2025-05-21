#!/usr/bin/env bash
# snapshot.sh – extract __webpack_modules__ from Spotify’s V8 snapshot
# Works on Intel & Apple-Silicon, no BOM tricks needed.

APP="$1"            # …/Spotify.app
OUT="$2"            # path for xpui-modules.js slice

BASE="$APP/Contents/Frameworks/Chromium Embedded Framework.framework/Resources"
for cand in \
  "$BASE/v8_context_snapshot.$(uname -m).bin" \
  "$BASE/v8_context_snapshot.bin"
do
  [[ -f "$cand" ]] && SNAP="$cand" && break
done
[[ -z "$SNAP" ]] && { echo "snapshot.bin not found"; exit 1; }

START="76006100720020005F005F007700650062007000610063006B005F006D006F00640075006C00650073005F005F003D007B00"
END="78007000750069002D006D006F00640075006C00650073002E006A0073002E006D0061007000"

perl -e '
  use Encode "decode"; local $/;
  open my $fh,"<:raw",$ARGV[0] or die $!;
  my $blob=<$fh>; close $fh;
  my ($start,$end)=map{pack"H*",$_} @ARGV[1,2];
  my $i=index($blob,$start); $i>=0 or die "start marker";
  my $j=index($blob,$end,$i)+length($end); $j>length($end) or die "end marker";
  open my $out,">",$ARGV[3] or die $!;
  print $out decode("UTF-16LE",substr($blob,$i,$j-$i));
'  "$SNAP" "$START" "$END" "$OUT"
