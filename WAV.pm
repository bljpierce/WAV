package WAV;
use strict;
use warnings;
use Carp qw(croak);
use Fcntl qw(O_CREAT O_RDONLY O_WRONLY SEEK_SET);


use constant {
    WAV_HDR_LEN        => 44, # size of a canonical wav header in bytes
    WAV_MODE_READ      => 0,
    WAV_MODE_WRITE     => 1,
    WAV_FORMAT_PCM	   => 0x0001,
    WAV_FORMAT_FLOAT   => 0x0003,
    MAX_SIGNED_INT_16  => 32767,
    MAX_SIGNED_INT_24  => 8388608,
    MAX_SIGNED_INT_32  => 2147483647,
};


sub new {
    my ($class, $arg_ref) = @_;

    if (@_ < 2) {
        croak "not enough arguments given";
    }
    elsif (ref $arg_ref ne 'HASH') {
        croak 'not a hash reference';
    }

    _check_args($arg_ref);

    my $self = bless {}, $class;

    if ($arg_ref->{mode} eq 'r') {
        $self->_init_read($arg_ref);
    }
    elsif ($arg_ref->{mode} eq 'w') {
        $self->_init_write($arg_ref);
    }

    return $self;
}


sub _check_args {
    my ($arg_ref) = @_;

    if (!exists $arg_ref->{file}) {
        croak "no file parameter given";
    }
    elsif (!exists $arg_ref->{mode}) {
        croak "no mode parameter given";
    }
    elsif ($arg_ref->{mode} ne 'r' && $arg_ref->{mode} ne 'w') {
        croak "unrecognised mode given (should be 'r' or 'w')";
    }

    if ($arg_ref->{mode} eq 'w') {
        if (!exists $arg_ref->{samp_rate}) {
            croak "no samp_rate parameter given\n";
        }
        elsif (!exists $arg_ref->{num_chans}) {
            croak "no num_chans parameter given\n";
        }
        elsif (!exists $arg_ref->{format}) {
            croak "no format parameter given\n";
        }
        elsif ($arg_ref->{format} ne 'pcm_16' && $arg_ref->{format} ne 'pcm_24'
               && $arg_ref->{format} ne 'pcm_32' && $arg_ref->{format} ne 'float')
        {
            croak "unrecognised format given (can be 'pcm_16', "
                    . "'pcm_24', 'pcm_32' or 'float')"; 
        }	
    }
}


sub _init_read {
	my ($self, $arg_ref) = @_;
	
    sysopen $self->{fh}, $arg_ref->{file}, O_CREAT | O_RDONLY or croak "$!";

    $self->{is_writable} = 0;

    $self->_read_hdr();
}


sub _init_write {
    my ($self, $arg_ref) = @_;

    sysopen $self->{fh}, $arg_ref->{file}, O_CREAT | O_WRONLY or croak "$!";

    if ($arg_ref->{format} eq 'pcm_16') {
        $self->{num_bits} = 16;
        $self->{pack_str} = 's<*';
        $self->{max_int } = MAX_SIGNED_INT_16;
    }
    elsif ($arg_ref->{format} eq 'pcm_24') {
        $self->{num_bits} = 24;
        $self->{max_int } = MAX_SIGNED_INT_24;
    }
    elsif ($arg_ref->{format} eq 'pcm_32') {
        $self->{num_bits} = 32;
        $self->{pack_str} = 'l<*';
        $self->{max_int } = MAX_SIGNED_INT_32;
    }
    elsif ($arg_ref->{format} eq 'float') {
        $self->{num_bits} = 32;
        $self->{pack_str} = 'f*';
    }

    $self->{format} = $arg_ref->{format};

    $self->{samp_rate  } = $arg_ref->{samp_rate};
    $self->{num_chans  } = $arg_ref->{num_chans};
    $self->{align      } = $self->{num_chans} * ($self->{num_bits} / 8);
    $self->{is_writable} = 1;

    # construct & write a dummy header to disk
    # will be over written later
    $self->{hdr_len} = $self->{format} eq 'float' ? 58 : 44;
	
    my $hdr = "Z" x $self->{hdr_len};
    my $buf = pack "A*", $hdr;

    syswrite $self->{fh}, $buf;
}


#   Parse a wav file header, checking and extracting relevant
#   information from the RIFF, fmt and data chunks. Any optional chunks
#   (e.g cue, fact, plst, adlt, etc) are skipped. 
sub _read_hdr {
    my ($self) = @_;

    my $buf;
    my $is_riff = 0;
	
    while (1) {
        sysread $self->{fh}, $buf, 8;
        my ($chunk_id, $chunk_len) = unpack 'A4V', $buf;
        if ($chunk_id eq 'RIFF') {
            $is_riff = 1;
            # check that we've got a wav file
            sysread $self->{fh}, $buf, 4 or croak "$!";
            if (unpack 'A4', $buf ne 'WAVE') {
                croak "not a WAV file";
            } 
        }
        elsif ($chunk_id eq 'fmt') { # why doesn't $chunk_id eq 'fmt ' work?
            sysread $self->{fh}, $buf, $chunk_len;
            $self->_decode_fmt_chk($buf);		
        }
        elsif ($chunk_id eq 'data') {
            $self->{data_size } = $chunk_len;
            $self->{num_frames} = $self->{data_size} / $self->{align};
            last;
        }
        elsif ($chunk_id =~ /[\w\s]{3}/i) {
            # skip any chunks we're not interested in
            if ($is_riff) {
                sysread $self->{fh}, $buf, $chunk_len or croak "$!";
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
    @{ $self }{ qw/code num_chans samp_rate bits_per_sec align num_bits/ }
        = unpack '(ssllss)<', $buf;
				
    if ($self->{code} == WAV_FORMAT_PCM) {
        if ($self->{num_bits} < 16 && $self->{num_bits} > 32
            && $self->{num_bits} % 8 != 0)
        {
            croak 'unsupported bit depth';
        }
    }
    elsif ($self->{code} == WAV_FORMAT_FLOAT) {
        if ($self->{num_bits} != 32) {
            croak 'unsupported bit depth';
        }
    }
    else {
        croak 'unsupported format';
    }
		
    $self->_set_read_attrs();
}


sub _set_read_attrs {
    my ($self) = @_;

    if ($self->{code} == WAV_FORMAT_PCM) {
        if ($self->{num_bits} == 16) {
            $self->{format  } = 'pcm_16';
            $self->{pack_str} = 's<*';
            $self->{max_int } = MAX_SIGNED_INT_16;
        }
        elsif ($self->{num_bits} == 24) {
            $self->{format  } = 'pcm_24';
            $self->{max_int } = MAX_SIGNED_INT_24;
        }
        elsif ($self->{num_bits} == 32) {
            $self->{format  } = 'pcm_32';
            $self->{pack_str} = 'l<*';
            $self->{max_int } = MAX_SIGNED_INT_32;
        }
    }
    elsif ($self->{code} == WAV_FORMAT_FLOAT) {
        $self->{format  } = 'float';
        $self->{pack_str} = 'f*';
    }

    $self->{bytes_read} = 0;
}


sub read_floats_a {
    my ($self, $num_frames) = @_;

    if (@_ < 2) {
        croak "error: not enough arguments given";
    }

    $num_frames *= $self->{align};

    # read audio frames into $buf
    my ($num_bytes, $buf);
    $num_bytes = sysread $self->{fh}, $buf, $num_frames // croak "$!";

    $self->{bytes_read} += $num_bytes;

    if ($self->{bytes_read} > $self->{data_size}) {
        $buf = substr
            $buf,
            0,
            $num_bytes - ($self->{bytes_read} - $self->{data_size});
	}
	
    my @samps;
    if ($self->{format} ne 'pcm_24') {
        @samps = unpack $self->{pack_str}, $buf;
    }
    else { # unpack little endian 24bit signed ints
        @samps = unpack 'l<*', pack '(a3x)*', unpack '(a3)*', $buf;
    }

    # rescale audio data to between -1.0 & +1.0
    if (index($self->{format}, 'pcm') != -1) {
        my $max_int = $self->{max_int};
        for my $v (@samps) {
            $v /= $max_int;
        }
    }

    return $num_bytes ? \@samps : '';
}


#	Constructs a canonical wav file header and writes it to disk.
sub _write_hdr {
	my ($self) = @_;

    $self->{num_frames} = $self->{data_size} / $self->{align};

    my $needs_padding = 0;
    
    if ($self->{num_frames} % 2 != 2) { #check this is correct
        $self->{hdr_len}++;
        $needs_padding = 1;
    }

    my $buf;
    # construct the RIFF chunk
    $buf  = pack 'A4V', 'RIFF', $self->{data_size} + $self->{hdr_len} - 8;
    $buf .= pack 'A4', 'WAVE';

    # construct the fmt subchunk
    $buf .= pack
        'A4VvvVVvv',
        'fmt ',
        $self->{format} eq 'float' ? 18 : 16, 
        $self->{format} eq 'float' ? WAV_FORMAT_FLOAT : WAV_FORMAT_PCM,
        $self->{num_chans},
        $self->{samp_rate},
        $self->{samp_rate} * $self->{align},
        $self->{align},
        $self->{num_bits};

    if ($self->{format}	eq 'float') {
        $buf .= pack 'v', 0;
        # construct the fact subchunk
        $buf .= pack
            'A4VV', 
            'fact',
            4,
            $self->{num_frames};
    }

    # construct the data subchunk
    my $data = 'A4V';

    if ($needs_padding) {
        $data .= 'x';
    }

    $buf .= pack $data, 'data', $self->{data_size};
	
    syswrite $self->{fh}, $buf or croak "$!";
}


sub write_floats_a {
    my ($self, $samps_ref) = @_;
    
    if (@_ < 2) {
        croak "not enough arguments given";
    }
    elsif (ref $samps_ref ne 'ARRAY') {
        croak "argument not an array reference";
    }

    # rescale PCM data to between -$max_int & +$max_int
    if (index($self->{format}, 'pcm') != -1) {
        my $max_int = $self->{max_int};
        for my $v (@{ $samps_ref }) {
            $v *= $max_int;
        }
    }

    my $buf;
    if ($self->{format} ne 'pcm_24') {
        $buf = pack $self->{pack_str}, @{ $samps_ref };
    }
    else { # unpack little endian 24bit signed ints
        $buf = join '', unpack '(a3x)*', pack 'l<*', @{ $samps_ref };
    }

    my $num_bytes = length $buf;

    $self->{data_size} += $num_bytes;

    syswrite $self->{fh}, $buf or croak "$!";

    return $num_bytes / $self->{align};
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


sub format {
    return $_[0]->{format};
}


sub finish {
    my ($self) = @_;

    if ($self->{is_writable}) {
        sysseek $self->{fh}, 0, SEEK_SET or croak "$!";
        $self->_write_hdr();
    }
	
    if ($self->{fh}) {
        close $self->{fh};
    }

    $self->{finished} = 1;
}


sub DESTROY {
    my ($self) = @_;
    
    if (!exists $self->{finished}) {
        $self->finish();
    }
}


1;


__END__

=head1 NAME

 WAV - read and write mono/stereo uncompressed WAV files.

=head1 VERSION

 VERSION 0.0001

=head1 SYNOPSIS

 use WAV;
 
 # create a Wav object for reading
 my $wf_in = WAV->new({ file => 'in.wav', mode => 'r' });
 
 # create a Wav object for writing
 my $wf_out = WAV->new({ 
     file      => 'out.wav', 
     mode      => 'w', 
     num_chans => $wf_in->num_chans, 
     samp_rate => $wf_in->samp_rate, 
     format    => 'float', 
 });
 
 # processing loop
 while (my $frames_ref = $wf->read_floats_a(1024)) { # read chunk
     ##################################
     # can do further processing here #
     ##################################
     $wf_out->write_floats_a($frames_ref); # write chunk
 }

=head1 DESCRIPTION

 A module for reading and writing mono/stereo uncompressed WAV files.
 The following uncompressed formats are currently supported: 16, 24,
 32 bit integers and 32 bit floats.

=head1 CONSTRUCTOR

=head2 new($hash_ref_of_named_args)

 Creates a WAV object for reading or writing WAV files. It takes a hash
 reference of named arguments. 
 
 For reading WAV files, 'file' and 'mode' arguments must be given. The 
 'mode' argument should be given the value 'r'.
 
 For writing WAV files, 'file', 'mode', 'num_chans', 'samp_rate' and
 'format' arguments must be given. The mode argument should be given the
 value 'w'. The 'format' argument accepts the following strings as values:
 'pcm_16', 'pcm_24', 'pcm_32' and 'float'. 
 
 If there was a problem creating the object this method will croak.

=head1 METHODS

=head2 read_floats_a($num_frames)

 Reads $num_frames and returns a reference to an array containing floating
 point frames. Any conversions from ints to floats are done automatically.
 Returns false when there are no more frames to be read. This method will
 croak if there was a problem reading the data. 

=head2 write_floats_a($frames_ref)

 Takes a reference to an array of audio frames (floats), converting them to 
 ints if necessary, then writes them to disk. The number of frames written
 is returned. This method will croak if there was a problem writing the 
 data.

=head2 finish()

 Closes the file handle and flushes any unwritten data to disk. This method 
 will be called by the destructor.

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

