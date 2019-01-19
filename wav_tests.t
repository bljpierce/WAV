# Test suite for WAV.pm - these tests check that WAV.pm correctly processes
# valid WAV files. They cover about 74% of the WAV.pm code.

use strict;
use warnings;

use lib '.';
use WAV;
use Test::More tests => 59;
use File::Temp 'tempdir';

my $dir = tempdir( CLEANUP => 1 );

# check mono WAV file is processed correctly

# create WAV object for reading
my $r = WAV->new('sine_16_44100_mono.wav', 'r');

ok ref $r eq 'WAV', 'object is a WAV';

#  check WAV header is parsed correctly
ok $r->num_chans  == 1,        'num_chans is 1';
ok $r->samp_rate  == 44100,    'samp_rate is 44100';
ok $r->num_frames == 22050,    'num_frames is 22050';
ok $r->samp_fmt   eq 'pcm_16', 'samp_fmt is pcm_16';

# check reading works
my $frames = $r->read_floats_aref(512);
ok ref $frames eq 'ARRAY', 'got an aref';
ok @$frames    == 512,     'read 512 frames into aref';

my $buf = $r->read_floats_str(512);
ok length $buf == 2048, 'read 512 frames (2048 bytes) into packed string';

# check move_to and frame_pos work
ok $r->move_to(22050) == 22050, 'move_to frame offset 22050';
ok $r->frame_pos      == 22050, 'frame_pos returns 22050';
ok $r->move_to(0)     == 0,     'move_to frame offset 0';
ok $r->frame_pos      == 0,     'frame_pos returns 0';

# create WAV object for writing
my $file = "$dir/" . 'sine_temp.wav';
my $w = WAV->new($file, 'w', 'pcm_16', 1, 44100);

ok ref $w eq 'WAV', 'object is a WAV';

# check writing works
$frames = $r->read_floats_aref(11025);
$w->write_floats_aref($frames);
$w->finish;

ok $w->num_frames == 11025,    'num_frames is 11025';
ok $w->num_chans  == 1,        'num_chans is 2';
ok $w->samp_fmt   eq 'pcm_16', 'samp_fmt is pcm_16';
ok $w->samp_rate  == 44100,    'samp_rate is 44100';


# check stereo WAV file is processed correctly

# create WAV object
$r = WAV->new('square_24_44100_stereo.wav', 'r');

ok ref $r eq 'WAV', 'object is a WAV';

#  check WAV header is parsed correctly
ok $r->num_chans  == 2,        'num_chans is 1';
ok $r->samp_rate  == 44100,    'samp_rate is 44100';
ok $r->num_frames == 22050,    'num_frames is 22050';
ok $r->samp_fmt   eq 'pcm_24', 'samp_fmt is pcm_24';
ok $r->num_samps  eq 44100,    'num_samps is 44100';
ok $r->duration   eq 0.5,      'duaration is 0.5';

# check reading works
$frames = $r->read_floats_aref(1024);

ok ref $frames    eq 'ARRAY', 'got an aref';
ok @$frames       == 2048,    'read 1024 frames into aref'; 

$buf = $r->read_floats_str(1024);

ok length $buf == 8192, 'read 1024 frames (8192 bytes) into packed string';

# check move_to and frame_pos work
ok $r->move_to(22050) == 22050, 'move_to frame offset 22050';
ok $r->frame_pos      == 22050, 'frame_pos returns 22050';
ok $r->move_to(0)     == 0,     'move_to frame offset 0';
ok $r->frame_pos      == 0,     'frame_pos returns 0';

# create WAV object for writing
$file = "$dir/" . 'square_temp.wav';
$w = WAV->new($file, 'w', 'pcm_24', 2, 44100);

ok ref $w eq 'WAV', 'object is a WAV';

# check writing works
$frames = $r->read_floats_aref(11025);
$w->write_floats_aref($frames);
$w->finish;

ok $w->num_frames == 11025,    'num_frames is 11025';
ok $w->num_chans  == 2,        'num_chans is 2';
ok $w->samp_fmt   eq 'pcm_24', 'samp_fmt is pcm_24';
ok $w->samp_rate  == 44100,    'samp_rate is 44100';

$r = WAV->new('sine_float_44100_mono.wav', 'r');

ok ref $r eq 'WAV', 'object is a WAV';

#  check WAV header is parsed correctly
ok $r->num_chans  == 1,        'num_chans is 1';
ok $r->samp_rate  == 44100,    'samp_rate is 44100';
ok $r->num_frames == 22050,    'num_frames is 22050';
ok $r->samp_fmt   eq 'float',  'samp_fmt is float';

# check reading works
$frames = $r->read_floats_aref(512);
ok ref $frames eq 'ARRAY', 'got an aref';
ok @$frames    == 512,     'read 512 frames into aref';

$buf = $r->read_floats_str(512);
ok length $buf == 2048, 'read 512 frames (2048 bytes) into packed string';

$r = WAV->new('noise_32_44100_mono.wav', 'r');

#  check WAV header is parsed correctly
ok $r->num_bits  == 32,    "num_bits is 32";

$file = "$dir/" . 'noise_temp.wav';
$w = WAV->new($file, 'w', 'float', 1, 44100);

$frames = $r->read_floats_str(1024);

ok length $frames == 4096, 'read 1024 frames (4096 bytes) into packed string';

$r = WAV->new('sine_8_44100_mono.wav', 'r');

ok ref $r eq 'WAV', 'object is a WAV';
# check WAV headr is parsed correctly
ok $r->num_chans  == 1,        'num_chans is 1';
ok $r->samp_rate  == 44100,    'samp_rate is 44100';
ok $r->num_frames == 22050,    'num_frames is 22050';
ok $r->samp_fmt   eq 'pcm_8',  'samp_fmt is pcm_8';
ok $r->num_bits   == 8,        'num_bits is 8';

# check reading works
$frames = $r->read_floats_aref(512);
ok ref $frames eq 'ARRAY', 'got an aref';
ok @$frames    == 512,     'read 512 frames into aref';

# create WAV object for writing
$file = "$dir/" . 'sine_temp.wav';
$w = WAV->new($file, 'w', 'pcm_8', 1, 44100);

ok ref $w eq 'WAV', 'object is a WAV';

# check writing works
$frames = $r->read_floats_aref(11025);
$w->write_floats_aref($frames);
$w->finish;

ok $w->num_frames == 11025,    'num_frames is 11025';
ok $w->num_chans  == 1,        'num_chans is 1';
ok $w->samp_fmt   eq 'pcm_8', 'samp_fmt is pcm_8';
ok $w->samp_rate  == 44100,    'samp_rate is 44100';