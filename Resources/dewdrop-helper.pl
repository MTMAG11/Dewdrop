#!/usr/bin/perl
# Dewdrop core-sensors helper (runs as root via launchd).
# Streams Apple's powermetrics output, but ONLY while the Dewdrop app is open (the app touches a flag file).
# It only reads sensors and writes one world-readable file. It changes nothing else on the system.
use strict;
use warnings;
use IO::Select;

my $dir  = $ENV{DEWDROP_DIR}  // "/Library/Application Support/Dewdrop";
my $flag = $ENV{DEWDROP_FLAG} // "/private/tmp/com.rishaan.dewdrop.active";
my $pm   = $ENV{DEWDROP_PM}   // "/usr/bin/powermetrics";
my $data = "$dir/power.plist";
my $tmp  = "$dir/power.plist.tmp";
$| = 1;

sub fresh { my @s = stat($flag); return (@s && (time - $s[9]) < 6) ? 1 : 0; }

while (1) {
    if (!fresh()) { sleep 3; next; }
    my $pid = open(my $fh, "-|", $pm, "--samplers", "cpu_power,gpu_power,ane_power,thermal", "-i", "1000", "-f", "plist");
    if (!$pid) { sleep 3; next; }
    my $sel = IO::Select->new($fh);
    my $buf = "";
    while (1) {
        my @ready = $sel->can_read(2);               # wake at least every 2 s so we notice when the app closes
        if (@ready) {
            my $n = sysread($fh, my $chunk, 65536);
            last unless $n;                          # stream ended
            $buf .= $chunk;
            while ($buf =~ s/^(.*?<\/plist>)//s) {
                my $doc = $1;
                $doc =~ s/^[\0\s]+//;
                if (length($doc) > 200 && open(my $out, ">", $tmp)) {
                    print $out $doc;
                    close($out);
                    chmod 0644, $tmp;
                    rename($tmp, $data);
                }
            }
            $buf = "" if length($buf) > 4_000_000;
        }
        last unless fresh();                         # app closed: stop sampling
    }
    kill 'TERM', $pid;
    close($fh);
    sleep 1;
}
