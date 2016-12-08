#!/usr/bin/perl

use File::Basename;
use File::Copy;
use File::Temp qw/ tempfile tempdir /;

use warnings;
use strict;

#
# Linux Script for playing film with 2 srt subtitles.
# The script convert the two srt subtitles to sass format, and plays the film.
#
# Configuracion
#   User configuration variables under 'User adaptable variables'.
#
# Info
#   Both subtitles have to be in srt format.
#   Tested on Ubuntu >=14, ..
#   
# Installation
#   For caja (ubuntu) copy this script to:
#       ~/.config/caja/scripts/
#   For nemo (linux mint, etc) depends on the version:
#       a) ~/.gnome2/nemo-scripts/
#       b) ~/.local/share/nemo/scripts/, ..)
#
# ----------------------------------------------------------------
#
# To dos: 
#   Conver srts to user encoding 
#   Probar dependencias sobre sistema limpio
#
# ----------------------------------------------------------------
#
#   Armando Aznar GPL v2

############################
#                          #
# User adaptable variables #
#                          #
############################

my $PLAY_AT_END=1;
my @PREFERRED_PLAYER_ORDER = ("smplayer","vlc","mpv","miro");

# Above subtitle style
my %l1s= 
   (
      # lang 1 style
      Name              => "lang1style",
      Fontname          => "Arial",
      Fontsize          => 60,
      PrimaryColour     => 16777215,
      SecondaryColour   => 65535,
      TertiaryColour    => 65535,
      BackColour        => -2147483640,
      Bold              => -1,
      Italic            => 0,
      BorderStyle       => 1,
      Outline           => 8,
      Shadow            => 0,
      Alignment         => 6,
      MarginL           => 30,
      MarginR           => 30,
      MarginV           => 30,
      AlphaLevel        => 0,
      Encoding          => 0,
);

# Bottom subtitle style
my %l2s=
   (
      # lang 2 style
      Name              => "lang2style",
      Fontname          => "Arial",
      Fontsize          => 60,
      PrimaryColour     => 16777215,
      SecondaryColour   => 65535,
      TertiaryColour    => 65535,
      BackColour        => -2147483640,
      Bold              => -1,
      Italic            => 0,
      BorderStyle       => 1,
      Outline           => 8,
      Shadow            => 0,
      Alignment         => 2,
      MarginL           => 30,
      MarginR           => 30,
      MarginV           => 30,
      AlphaLevel        => 0,
      Encoding          => 0,
);

##################
#                #
#   The code     #
#                #
##################

my $DEVEL = 0;
my $bilingual_sufix = "";

sub usage 
{
    if ( executed_from_x() ) {
        show_user_msg("info","Film with two subtitles not found, try selecting the film and the two subtitles.");
    }else{
        show_user_msg("info","$0 <movie file> \n\tor\n$0 <movie file> <srt_sub_1> <srt_sub_2>\n");
    }
}

sub main
{
    my @files = get_needed_files_paths();

    if (scalar @files == 3){
        prepare_srt_file($_) foreach ( ($files[1],$files[2]) );
        my ($file,$directory,$name,$ext) = get_filepath_components($files[0]);
        my @srt_pair = get_srt_pair_files_data($files[1],$files[2]);
        my $bilingual_sub_path = "$directory/${name}$bilingual_sufix.ass";
        create_sas_sub($bilingual_sub_path,@srt_pair);
        play_film($files[0],$bilingual_sub_path) if ($PLAY_AT_END);
    }else{
        usage();
        exit(1);
    }
}

sub get_filepath_components
{
    my ($filepath) = @_;
    my $file_name = basename($filepath);
    my $directory = dirname($filepath);
    my ($name,$ext) = $file_name =~ /(.*)(\.[^.]+)$/;
    return ($file_name,$directory,$name,$ext);
}

# Return an array with the 3 needed files in the proper order : movie file, srt 1 file, srt 2 file
# Eiter way return an empty array 
sub get_needed_files_paths
{
    my @files = get_all_user_files();

    if (scalar @files == 1){
        my @srt_files = find_the_two_subtitles($files[0]);
        return ($files[0],@srt_files) if (scalar @srt_files == 2);
        return ();
    }elsif (scalar @files == 3) {
        return get_correct_files_order(@files);
    }else{
        return ();
    }
}

sub get_all_user_files
{
    my ($filepaths) = @_;

    my @files;

    if ( executed_from_x() ) {
        # Ubuntu 15 Mate
        $filepaths =  $ENV{'NAUTILUS_SCRIPT_SELECTED_FILE_PATHS'} if (defined $ENV{'NAUTILUS_SCRIPT_SELECTED_FILE_PATHS'});
        # Linux Mint 14
        $filepaths =  $ENV{'NEMO_SCRIPT_SELECTED_FILE_PATHS'} if (defined $ENV{'NEMO_SCRIPT_SELECTED_FILE_PATHS'});
        @files = split("\n",$filepaths);
    }else{
        if (defined $ARGV[1] && defined($ARGV[2]) ){
            @files = ($ARGV[0],$ARGV[1],$ARGV[2]);
        }elsif (defined $ARGV[0] ){
            @files = ($ARGV[0]);
        }else{
            @files = ();
        }
    }

    return @files;
}

sub executed_from_x
{
    return 1 if (defined $ENV{'NAUTILUS_SCRIPT_SELECTED_FILE_PATHS'} || defined $ENV{'NEMO_SCRIPT_SELECTED_FILE_PATHS'});
    return 0;
}

sub get_srt_file_data
{
    my @content = @{$_[0]};
    my @registers;
    my $line_register ={};
    my $line = 0;
    my $phase = 0;
        #0: line number 
        #1: timing
        #2: getting text
    foreach (@content){
        chomp;
        $line++;
        if ($phase == 0){
            next unless length;
            if ($DEVEL ) {
                show_user_msg_and_die("error","Invalid line number in line $line:$_") unless m/^\d+$/;
            }else{
                next unless m/^\d+$/;
            }
            my ($num) = ($_ =~ /^(\d+)$/);
            $line_register= {};
            $line_register->{"text"} = "";
            $line_register->{"num"} = $num;
            $phase++;
        }elsif ($phase == 1){
            if ($DEVEL){
                show_user_msg_and_die("error","Invalid timing at line $line") unless m/^(\d\d):(\d\d):(\d\d)\,(\d\d\d)\s*-->\s*(\d\d):(\d\d):(\d\d)\,(\d\d\d)/;
            }else{
                next unless m/^(\d\d):(\d\d):(\d\d)\,(\d\d\d)\s*-->\s*(\d\d):(\d\d):(\d\d)\,(\d\d\d)/;
            }
            my ($time1,$time2) = ($_ =~ /^(.*?)\s*-->\s*(.*)$/ );
            $line_register->{"time1"} = $time1;
            $line_register->{"time2"} = $time2;
            $phase++;
        }elsif ($phase == 2){
            if (length) { 
                $_  =~ s/^\s+|\s+$//g;
                $line_register->{"text"} .= "$_\n";
            }else{
                push (@registers, $line_register);
                $phase=0;
            }
        }
    }
    return @registers;
}

sub prepare_srt_file
{
    my ($srt_file) = @_;
    # -f Force, sometimes there are binary characters
    my $ret = system("dos2unix","-f",$srt_file);
    if ( $ret != 0 ) {
        show_user_msg_and_die("error","Error trying to conver file to unix format");
    }
}

sub play_film
{
    my ($film_path,$sub_path) = @_;
    foreach (@PREFERRED_PLAYER_ORDER){
        if (syswhich($_) ne ""){
            system($_,$film_path,$sub_path);
            return 1;
        }
    }
    return 0;
}

sub show_user_msg
{
    my ($typemsg,$msg) = @_;
    if ( executed_from_x() ){
        $typemsg = "info" if ($typemsg ne "info" and $typemsg ne "error");
        system("zenity","--$typemsg","--text=$msg") if (syswhich("zenity") ne "");
    }else{
        print $msg;
    }
}

sub show_user_msg_and_die
{
    my ($typemsg,$msg) = @_;
    show_user_msg($typemsg,$msg);
    die($msg);
}


sub get_srt_pair_files_data 
{
    my ($file_1,$file_2) = @_;
    my @srt_pair;
    foreach ( ($file_1,$file_2) ){
        open FILE,"<$_" or do { show_user_msg("error","Cant find file $_ \n $!"); exit(1); };
        my @srt_lines= <FILE>;
        close FILE;
        my @regs = get_srt_file_data(\@srt_lines);
        push(@srt_pair,\@regs);
    }
    return @srt_pair;
}

sub create_sas_sub
{
    my ($file_sas,@srt_pair) = (@_);

    open FILE ,">$file_sas" or show_user_msg_and_die("error","Cant open sas file to write: $file_sas $!");
    print_header(*FILE);
    print FILE get_ass_line($_,"lang1style") foreach ( @ { $srt_pair[0] } );
    print FILE get_ass_line($_,"lang2style") foreach ( @ { $srt_pair[1] } );
    close FILE;
}

sub get_ass_line
{
    my ($srt_reg,$line_style) = @_;
    my $time_1 = srt_time_to_ass_format($srt_reg->{"time1"});
    my $time_2 = srt_time_to_ass_format($srt_reg->{"time2"});
    my $text   = srt_text_to_ass_format($srt_reg->{"text"});
    my $line   = "Dialogue: Marked=0,$time_1,$time_2,$line_style,,0000,0000,0000,,".$text;
    # Some players dont like two digits like that..
    $line =~ s/:0(.):/:$1:/g;
    $line =~ s/,0(.):/,$1:/g;
    return $line."\n";
}

sub srt_time_to_ass_format
{
    my ($srt_time) = @_;
    $srt_time =~ s/,/./g;
    $srt_time = substr($srt_time, 0, -1);
    return $srt_time;
}

sub srt_text_to_ass_format
{
    my ($text) = @_;
    $text =~ s/\n/\\N/g;
    $text =~ s/<.*?>//g;
    return $text;
}

sub print_header
{
    my ($fh) = @_;
my ($FILE_HANDLER) = @_;
print $fh "
[Script Info]
Title:
; Converted by the Subtitle Converter developed by  Armando AR
Original Script:
Original Translation:
Original Editing:
Original Timing:
Original Script Checking:
ScriptType: v4.00
Collisions: Normal
PlayResY: 1024
PlayDepth: 0
Timer: 100,0000

[V4 Styles]
Format: Name,       Fontname,   Fontsize, PrimaryColour, SecondaryColour, TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding
Style: ".$l1s{'Name'}.",".$l1s{'Fontname'}.",".$l1s{'Fontsize'}.",".$l1s{'PrimaryColour'}.",".$l1s{'SecondaryColour'}.",".$l1s{'TertiaryColour'}.",".$l1s{'BackColour'}.",".$l1s{'Bold'}.",".$l1s{'Italic'}.",".$l1s{'BorderStyle'}.",".$l1s{'Outline'}.",".$l1s{'Shadow'}.",".$l1s{'Alignment'}.",".$l1s{'MarginL'}.",".$l1s{'MarginR'}.",".$l1s{'MarginV'}.",".$l1s{'AlphaLevel'}.",".$l1s{'Encoding'}."\n".
"Style: ".$l2s{'Name'}.",".$l2s{'Fontname'}.",".$l2s{'Fontsize'}.",".$l2s{'PrimaryColour'}.",".$l2s{'SecondaryColour'}.",".$l2s{'TertiaryColour'}.",".$l2s{'BackColour'}.",".$l2s{'Bold'}.",".$l2s{'Italic'}.",".$l2s{'BorderStyle'}.",".$l2s{'Outline'}.",".$l2s{'Shadow'}.",".$l2s{'Alignment'}.",".$l2s{'MarginL'}.",".$l2s{'MarginR'}.",".$l2s{'MarginV'}.",".$l2s{'AlphaLevel'}.",".$l2s{'Encoding'}."\n".
"[Events]
Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
";
}

sub print_register
{
    my ($reg) = @_;
    print "--------\n";
    print $reg->{"num"}."\n";
    print $reg->{"time1"}."\n";
    print $reg->{"time2"}."\n";
    print $reg->{"text"}."\n";
    print "--------\n";
}

sub is_correct_output_file
{
    my ($file) =  @_;

    return 0 if ($file eq "");
    if (-f $file ){
        return 1 if ( -w $file );
        return 0;
    }else{
        open FILE,">$file" or return 0;
        close FILE;
        return 1;
    }
}

sub get_correct_files_order
{
    my (@files) = @_;
    my @srt_files;
    my $movie_file;
    foreach (@files){
        push (@srt_files, $_) if ($_ =~ /\.srt/i);
        $movie_file = $_ if ($_ !~ /\.srt/i);
    }
    @srt_files=reverse sort(@srt_files);
    return ($movie_file,@srt_files) if ($movie_file ne "" and scalar @srt_files == 2);
    return ();
}

sub find_the_two_subtitles
{
    my ($filepath) = @_;
    my ($file,$directory,$name,$ext) = get_filepath_components($filepath);
    my @srt_files;
    opendir (DIR, $directory) or return ();
    while (my $dirfile = readdir(DIR)) {
        if ($dirfile =~ /^\Q$name\E/ && $dirfile =~ /\.srt$/i && ( $bilingual_sufix eq "" || $dirfile !~ /$bilingual_sufix\.srt/ ) ){
            push(@srt_files,$directory."/".$dirfile);
        }
    }
    @srt_files=reverse sort(@srt_files);
    return @srt_files if (scalar @srt_files == 2);
    return ();
}

sub syswhich
{
    my ($command)  = @_;
    my $ret = `which $command`;
    chomp($ret);
    return ($ret);
}

##########################################################

main();
