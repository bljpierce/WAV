package WAV;
use strict;
use warnings;

us[1;5Ce Carp 'croak';
use Fcntl qw(O_CREAT O_RDONLY O_WRONLY SEEK_SET);

use constant {
    WAV_FORMAT_PCM     => 1,
    WAV_FORMAT_FLOAT   => 3,
    MAX_UNSIGNED_INT_8 => 255,
    MAX_SIGNED_INT_16  => 32767,
    MAX_SIGNED_INT_24  => 8388607,
    MAX_SIGNED_INT_32  => 2147483647,
};


sub new {
    my $class = shift;
    _check_args(@_);
    my ($file, $mode, $samp_fmt, $num_chans, $samp_rate) = @_;

    my $self = bless { file => $file, hdr_len => 0, fh => undef }, $class;
    
    if ($mode eq 'r') {
        $self->_init_read;
    }
    elsif ($mode eq 'w') {
        $self->{samp_fmt } = $samp_fmt;
        $self->{num_chans} = $num_chans;
        $self->{samp_rate} = $samp_rate; 
        $self->_init_write;
    }

    return $self;
}


sub _check_args {
    my ($file, $mode, $samp_fmt, $num_chans, $samp_rate) = @_;
    
    
    if (@_ < 1) {
        croak 'missing $file and $mode arguments!';
    }
    elsif (@_ < 2) {
        croak 'missing $mode argument!';
    }
    
    if ($mode ne 'r' && $mode ne 'w') {
        croak "unrecognised \$mode argument: '$mode'!"; 
    }

    if ($mode eq 'w') {
        if (@_ < 3) {
            croak 'missing $samp_fmt, $num_chans'
                . ' and $samp_rate arguments!';
        }
        elsif (@_ < 4) {
            croak 'missing $num_chans and $samp_rate arguments!';
        }
        elsif (@_ < 5) {
            croak 'missing $samp_rate argument!';
        }
        
        if (!grep { $samp_fmt eq $_ } qw/pcm_8 pcm_16 pcm_24 pcm_32 float/) {
            croak "unrecognised \$samp_fmt value: '$samp_fmt'!"; 
        }
        elsif ($num_chans < 1 || $num_chans > 2) {
            croak "'$num_chans' channels of audio not supported!";
        }
        elsif ($samp_rate < 1) {
            croak '$samp_rate argument value must be positive!';
        }
    }
}


sub _init_read {
    my ($self) = @_;

    sysopen $self->{fh}, $self->{file}, O_RDONLY
         // croak "couldn't open $self->{file} for reading $!";

    $self->{is_writable} = 0;

    $self->_read_hdr;
}


sub _init_write {
    my ($self) = @_;

    sysopen $self->{fh}, $self->{file}, O_CREAT | O_WRONLY
         // croak "couldn't open $self->{file} for writing $!";
    
    my $format = $self->{samp_fmt};
    if ($format eq 'pcm_8') {
        $self->{num_bits} = 8;
        $self->{pack_str} = 'C*';
        $self->{max_int } = MAX_UNSIGNED_INT_8;
    }
    elsif ($format eq 'pcm_16') {
        $self->{num_bits} = 16;
        $self->{pack_str} = 'v!*';
        $self->{max_int } = MAX_SIGNED_INT_16;
    }
    elsif ($format eq 'pcm_24') {
        $self->{num_bits} = 24;
        $self->{max_int } = MAX_SIGNED_INT_24;
    }
    elsif ($format eq 'pcm_32') {
        $self->{num_bits} = 32;
        $self->{pack_str} = 'V!*';
        $self->{max_int } = MAX_SIGNED_INT_32;
    }
    elsif ($format eq 'float') {
        $self->{num_bits} = 32;
        $self->{pack_str} = 'f<*';
    }

    $self->{align      } = $self->{num_chans} * ($self->{num_bits} / 8);
    $self->{is_writable} = 1;

    # construct & write a dummy header to disk
    # will be over written later
    $self->{hdr_len} = $self->{samp_fmt} eq 'float' ? 58 : 44;

    my $hdr = "Z" x $self->{hdr_len};
    my $buf = pack "a*", $hdr;

    syswrite $self->{fh}, $buf
          // croak "couldn't write the dummy WAV file header $!";
}


#   Parse a WAV file header, checking and extracting relevant
#   information from the RIFF, fmt and data chunks. Any optional chunks
#   (e.g cue, fact, plst, adlt, etc) are skipped. 
sub _read_hdr {
    my ($self) = @_;

    my $buf;
    my $is_riff = 0;
    
    DECODE_CHUNK:
    while (1) {
        sysread $self->{fh}, $buf, 8
             // croak "couldn't read WAV header chunk $!";
        $self->{hdr_len} += 8;
        my ($chunk_id, $chunk_len) = unpack 'a4V', $buf;
        if ($chunk_id eq 'RIFF') {
            $is_riff = 1;
            # check that we've got a WAV file
            sysread $self->{fh}, $buf, 4
                 // croak "couldn't read 'WAVE' chunk $!";
            $self->{hdr_len} += 4;
            if (unpack 'a4', $buf ne 'WAVE') {
                croak "not a WAV file";
            } 
        }
        elsif ($chunk_id eq 'fmt ') {
            sysread $self->{fh}, $buf, $chunk_len
                 // croak "couldn't read 'fmt ' chunk $!";
            $self->{hdr_len} += $chunk_len;
            $self->_decode_fmt_chk($buf);		
        }
        elsif ($chunk_id eq 'data') {
            $self->{data_size } = $chunk_len;
            $self->{num_frames} = $self->{data_size} / $self->{align};
            last DECODE_CHUNK;
        }
        elsif ($chunk_id =~ /[\w\s]{4}/i) {
            # skip any chunks we're not interested in
            if ($is_riff) {
                $self->{hdr_len} += $chunk_len;
                sysread $self->{fh}, $buf, $chunk_len 
                     // croak "couldn't read uninteresting chunk $!";
            }
        }
        elsif (!$is_riff) {
            croak 'not a WAV file';
        }
        else {
            croak "can't read WAV file header";
        }
    }
    # the file handle is now pointing at the first frame
}


sub _decode_fmt_chk {
    my ($self, $buf) = @_;

    # extract relevant information
    @$self{ qw/code num_chans samp_rate bits_per_sec align num_bits/ }
        = unpack 'vvVVvv', $buf;

    if ($self->{code} == WAV_FORMAT_PCM) {
        if ($self->{num_bits} < 8 && $self->{num_bits} > 32) {
            croak 'unsupported sample bit depth';
        }
    }
    elsif ($self->{code} == WAV_FORMAT_FLOAT) {
        if ($self->{num_bits} != 32) {
            croak 'unsupported sample bit depth';
        }
    }
    else {
        croak 'unsupported sample format';
    }

    $self->_set_read_attrs;
}


sub _set_read_attrs {
    my ($self) = @_;

    if ($self->{code} == WAV_FORMAT_PCM) {
        if ($self->{num_bits} == 8) {
            $self->{samp_fmt} = 'pcm_8';
            $self->{pack_str} = 'C*';
            $self->{max_int } = MAX_UNSIGNED_INT_8;
        }
        elsif ($self->{num_bits} == 16) {
            $self->{samp_fmt} = 'pcm_16';
            $self->{pack_str} = 'v!*';
            $self->{max_int } = MAX_SIGNED_INT_16;
        }
        elsif ($self->{num_bits} == 24) {
            $self->{samp_fmt} = 'pcm_24';
            $self->{max_int } = MAX_SIGNED_INT_24;
        }
        elsif ($self->{num_bits} == 32) {
            $self->{samp_fmt} = 'pcm_32';
            $self->{pack_str} = 'V!*';
            $self->{max_int } = MAX_SIGNED_INT_32;
        }
    }
    elsif ($self->{code} == WAV_FORMAT_FLOAT) {
        $self->{samp_fmt} = 'float';
        $self->{pack_str} = 'f<*';
    }
    
    $self->{bytes_read} = 0;
}


sub read_floats_str {
    my ($self, $num_frames) = @_;
    
    if (@_ < 2) {
        croak 'missing $num_frames argument!';
    }
    elsif ($num_frames < 1 && $num_frames > $self->{num_frames}) {
        croak '$num_frames argument is out of bounds!';
    }
    
    my ($frames, $buf);
    if ($self->{samp_fmt} eq 'float') {
        $num_frames *= $self->{align};

        # read audio frames into $buf
        my $num_bytes;
        $num_bytes = sysread $self->{fh}, $buf, $num_frames
                          // croak "couldn't read audio frames $!";

        $self->{bytes_read} += $num_bytes;

        if ($self->{bytes_read} > $self->{data_size}) {
            $buf = substr
                $buf,
                0,
                $num_bytes - ($self->{bytes_read} - $self->{data_size});
        }
    }
    elsif ($frames = $self->read_floats_aref($num_frames)) {
        $buf = pack 'f<*', @$frames;
    }
    
    return length $buf ? $buf : '';
}


sub read_floats_aref {
    my ($self, $num_frames) = @_;

    if (@_ < 2) {
        croak 'missing $num_frames argument!';
    }
    elsif ($num_frames < 1 && $num_frames > $self->{num_frames}) {
        croak '$num_frames argument is out of bounds!';
    }

    $num_frames *= $self->{align};

    # read audio frames into $buf
    my ($num_bytes, $buf);
    $num_bytes = sysread $self->{fh}, $buf, $num_frames
                      // croak "couldn't read audio frames $!";

    $self->{bytes_read} += $num_bytes;

    if ($self->{bytes_read} > $self->{data_size}) {
        $buf = substr
            $buf,
            0,
            $num_bytes - ($self->{bytes_read} - $self->{data_size});
    }

    my @frames;
    if ($self->{samp_fmt} ne 'pcm_24') {
        @frames = unpack $self->{pack_str}, $buf;
    }
    else { # unpack little endian 24bit signed ints
        @frames = map { unpack('V!', qq[\x00$_]) / 256 } unpack '(a3)*', $buf;
    }

    # rescale audio data to between -1.0 & +1.0
    if (index($self->{samp_fmt}, 'pcm') != -1) {
        my $max_int = $self->{max_int};
        for my $s (@frames) {
            $s /= $max_int;
        }
    }

    return $num_bytes ? \@frames : '';
}


# Constructs a canonical WAV file header and writes it to disk.
sub _write_hdr {
    my ($self) = @_;

    $self->{num_frames} = $self->{data_size} / $self->{align};

    my $buf;
    # construct the RIFF chunk
    $buf  = pack 'a4V', 'RIFF', $self->{data_size} + $self->{hdr_len} - 8;
    $buf .= pack 'a4', 'WAVE';

    # construct the fmt subchunk
    $buf .= pack
        'a4VvvVVvv',
        'fmt ',
        $self->{samp_fmt} eq 'float' ? 18 : 16, 
        $self->{samp_fmt} eq 'float' ? WAV_FORMAT_FLOAT : WAV_FORMAT_PCM,
        $self->{num_chans},
        $self->{samp_rate},
        $self->{samp_rate} * $self->{align},
        $self->{align},
        $self->{num_bits};

    if ($self->{samp_fmt}	eq 'float') {
        $buf .= pack 'v', 0;   # not all parsers do this
        # construct the fact subchunk
        $buf .= pack
            'a4VV', 
            'fact',
            4,
            $self->{num_frames};
    }

    # construct the data subchunk
    my $data = 'a4V';

    $buf .= pack $data, 'data', $self->{data_size};
	
    syswrite $self->{fh}, $buf 
          // croak "couldn't write WAV file header $!";
}


sub write_floats_str {
    my ($self, $buf) = @_;
    
    if (@_ < 2) {
        croak 'missing $buf argument!';
    }
    
    my @frames = unpack "f<*", $buf;
    
    return $self->write_floats_aref(\@frames);
}


sub write_floats_aref {
    my ($self, $frames) = @_;
    
    if (@_ < 2) {
        croak 'missing $frames argument!';
    }
    elsif (ref $frames ne 'ARRAY') {
        croak '$frames argument not an array reference!';
    }

    # rescale PCM data to between -$max_int & +$max_int
    if (index($self->{samp_fmt}, 'pcm') != -1) {
        my $max_int = $self->{max_int};
        for my $v (@$frames) {
            $v *= $max_int;
        }
    }

    my $buf;
    if ($self->{samp_fmt} ne 'pcm_24') {
        $buf = pack $self->{pack_str}, @$frames;
    }
    else { # pack little endian 24bit signed ints
        $buf = pack '(V!X)*', @$frames;
    }

    my $num_bytes = length $buf;

    $self->{data_size} += $num_bytes;
    
    syswrite $self->{fh}, $buf
          // croak "couldn't write audio frames $!";

    return $num_bytes / $self->{align};
}


sub move_to {
    my ($self, $offset) = @_;
    
    if (@_ < 2) {
        croak 'missing $offset argument!';
    }
    
    # convert $offset to bytes
    $offset *= $self->{align};
    
    if ($offset < 0 && $offset > $self->{data_size}) {
        croak '$offset value out of bounds!';
    }
    
    $offset += $self->{hdr_len};
    
    my $pos = sysseek $self->{fh}, $offset, SEEK_SET
                   // croak "couldn't seek to byte $offset offset $!";
                   
    $pos -= $self->{hdr_len};
    
    return $pos / $self->{align}; # new frame position offset
}


sub frame_pos {
    my ($self) = @_;
    
    my $pos = sysseek $self->{fh}, 0, 1 // -1;
    
    return $pos > 0 ? ($pos - $self->{hdr_len}) / $self->{align} : -1;
}


sub num_chans {
    return $_[0]->{num_chans};
}


sub samp_rate {
    return $_[0]->{samp_rate};
}


sub num_frames {
    return $_[0]->{num_frames};
}


sub num_samps {
    return $_[0]->{num_frames} * $_[0]->{num_chans};
}


sub num_bits {
    return $_[0]->{num_bits};
}


sub duration {
    return $_[0]->{num_frames} / $_[0]->{samp_rate};
}


sub samp_fmt {
    return $_[0]->{samp_fmt};
}


sub finish {
    my ($self) = @_;

    if ($self->{is_writable} && $self->{data_size}) {
        sysseek $self->{fh}, 0, SEEK_SET
             // croak "couldn't SEEK to begining of file $!";
        $self->_write_hdr;
    }

    if ($self->{fh}) {
        close $self->{fh};
    }

    $self->{finished} = 1;
}


sub DESTROY {
    my ($self) = @_;
    
    if (!exists $self->{finished}) {
        $self->finish;
    }
}


1;


__END__

=head1 NAME

 WAV - read and write mono/stereo uncompressed WAV files.

=head1 VERSION

 VERSION 0.0003

=head1 SYNOPSIS

 use WAV;
 
 # create a WAV object for reading
 my $wf_in = WAV->new('in.wav', 'r');
 
 # create a WAV object for writing
 my $wf_out = WAV->new(
    'out.wav',
    'w',
    $in->samp_fmt,
    $in->num_chans,
    $in->samp_rate
 );
 
 # move file handle to frame 40000
 $wf_in->move_to(40000);
 
 # processing loop
 while (my $frames = $wf_in->read_floats_aref(1024)) { # read chunk of audio
     ##################################
     # can do further processing here #
     ##################################
     $wf_out->write_floats_aref($frames); # write chunk of audio
 }

=head1 DESCRIPTION

 A module for reading and writing mono/stereo uncompressed WAV files.
 The following uncompressed formats are supported: 16, 24 and 32 bit
 signed integers, 32 bit floats and 8 bit unsigned integers.

=head1 CONSTRUCTOR

=head2 new($file, $mode, $samp_fmt, $num_chans, $samp_rate)

 Creates a WAV object for reading or writing WAV files. 
 
 For reading and writing WAV files, '$file' and '$mode' arguments must be
 given. When reading the '$mode' argument should be given the value 'r' and
 when writing it should be given the value 'w'.  
 
 When writing WAV files three additional arguments need to be supplied.
 They are:
 
 $samp_fmt  - the sample format. This can be given one of the following
              strings as values: 'pcm_16', 'pcm_24' or 'pcm_32' for signed 
              integers, 'float' for 32 bit floats and 'pcm_8' for an 8 bit
              unsigned integer.
 
 $num_chans - number of channels of audio per frame. This can be given
              the value of 1 or 2 for mono and stereo respectively.
              
 $samp_rate - the sample rate in Hertz.
 
 If there was a problem creating the object this method will croak.

=head1 METHODS

=head2 read_floats_aref($num_frames)

 Reads $num_frames and returns a reference to an array containing floating
 point frames. Any conversions from ints to floats are done automatically.
 Returns false when there are no more frames to be read. This method will
 croak if there was a problem reading the data.
 
=head2 read_floats_str($num_frames)

 Same as the read_floats_aref method except that it returns a packed
 binary string instead of an array reference. The audio data in the
 binary string will be packed as 32 bit floats.

=head2 write_floats_aref($frames_ref)

 Takes a reference to an array of audio frames (floats), converting them to 
 ints if necessary, then writes them to disk. The number of frames written
 is returned. This method will croak if there was a problem writing the 
 data.
 
=head2 write_floats_str($buf)

 Same as the write_floats_aref method accept that it takes a packed binary
 string as an argument instead of an array reference. The audio data in the
 binary string should be packed as 32 bit floats.
 
=head2 move_to($offset)

 Moves the file handle to the given $offset. Note that the $offset value is
 expressed as frames. Also, giving $offset a value of 0 will move the file 
 handle to the begining of the audio data and not the begining of the WAV
 file. This method returns the new frame position if it was succesful and
 will croak otherwise.
 
=head2 frame_pos()

 Returns the current frame position of the file handle.
 
=head2 finish()

 Closes the file handle and flushes any unwritten data to disk. This method 
 will be called by the destructor but there may be occassions when you need
 to call this method explicitly. 

=head2 num_chans()

 Returns the number of channels per frame.

=head2 samp_rate()

 Returns the sample rate in Hertz.

=head2 num_frames()

 Returns the total number of frames of audio data.

=head2 num_samps()

 Returns the total number of samples of audio data. 

=head2 format()

 Returns the format of the audio data as a string.

=head2 duration()

 Returns the total duration of the audio in seconds.

=head1 AUTHOR

 Barry Pierce, bljpierce@gmail.com

=head1 COPYRIGHT & LICENCE

 Copyright (c) 2018, Barry Pierce.

