#!/usr/bin/perl
# Name:			kfilefactory.pl (kde4 version)
# Purpose:		easily upload a file or directory to filefactory.com
# Version:		0.1.1
# Date:			11.05.2010
# License:		GPLv2
# Author:		Robert Annessi <robert@annessi.at>


use warnings;
use strict;
use LWP::UserAgent;
use File::Temp qw/ tempdir /;
use File::Basename;
use POSIX qw(floor);
use HTTP::Request::Common qw(POST);
use Fcntl ':mode';


# global vars
$HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
my $pwlen = 60;
my $windowtitle = 'Share file';
my $error;
my $file_no = 1;
my $file_compress = 2;
my $file_password = 3;
my $filename;
my $filesize;
my $req;
my $password = "";


# check for right number of arguments
if ( $#ARGV != 0 ) {
  print "Usage: $0 <file|directory>\n";
  exit(0);
}


sub errorchk($$) {
  my ($ret, $txt) = (@_);
  if ( $ret != 0 ) {
    system("kdialog --title \"$windowtitle\" --error \"ERROR: $txt\"");
    exit(1);
  }
}


# check mode of file
sub check_flag($$) {
  my ($mode, $flag) = (@_);
  if ($mode & $flag) { 
    return 1;
  } else {
    return 0;
  }
}

# check if argument is file or directory
my $mode   = (stat($ARGV[0]))[2];
# generate zip file if argument is directory
if ($mode & S_IFDIR) {
  $file_compress = 0;
} elsif ($mode & S_IFREG) {
  $file_compress = 2;
} else {
  print "\"$ARGV[0]\" is neither a file nor a directory!";
  exit(3);
}


# ask user options
if ($file_compress == 0) {
  open (KDIALOG, "kdialog --title \"$windowtitle\" --radiolist \"Select options for uploading \"$ARGV[0]\" to filefactory.com:\" $file_compress \"Enable compression\" on $file_password \"Enable compression and (weak) password protection\" off |") or die $!;
} else {
  open (KDIALOG, "kdialog --title \"$windowtitle\" --radiolist \"Select options for uploading \"$ARGV[0]\" to filefactory.com:\" $file_no \"Do neither enable compression nor password protection\" on $file_compress \"Enable compression\" off $file_password \"Enable compression and (weak) password protection\" off |");
}


# evaluation of user options
my @options;
while (<KDIALOG>) {
  @options = split(" ", $_);
}
close KDIALOG;
# check return code of dialog
errorchk($?, "Cancelled by user!");
foreach my $element (@options) {
  $element =~ s/\"//g;
  if ($element == $file_compress) {
    $file_compress = 0;
  } elsif ($element == $file_password) {
    $file_password = 0;
  } elsif ($element == $file_no) {
    $file_no = 0;
  }
}



# initiate browser
my $ua = LWP::UserAgent->new;
$ua->agent("");    # do not identify
$ua->requests_redirectable( [ 'GET', 'POST' ] );
$ua->max_redirect(1);

# get start page from filefactory
my $response = $ua->get('http://www.filefactory.com/');
if ( !$response->is_success ) {
  errorchk(1, "$response->status_line");
}
#print $response->content;

# get upload url
if ( $response->content !~ /<form accept-charset="UTF-8" id="uploader" action="(http:\/\/[a-z0-9]+\.filefactory\.com\/upload\.php)" method="post" enctype="multipart\/form-data">/) {
  errorchk(1, "Parsing website for upload form failed!");
}
my $URL = "$1";
#print $response->content;


# extract filename, path and suffix from argument
( my $name, my $path, my $suffix ) = fileparse( "$ARGV[0]", "\.[^.]*" );
$name =~ s/\\//g;
$path =~ s/"//;
$suffix =~ s/"//;

# create zip file if requested
if ($file_compress == 0 || $file_password == 0) {
  # create temporary directory (will automatically be removed when the script exits)
  my $tempdir = tempdir( "kfilefactory.XXXXXXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

  my $filename_nosuffix = "$name$suffix";
  $filename = "$filename_nosuffix.zip";

  chdir "$path" or die "$!";

  # create zip file with random password
  if ($file_password == 0) {
    $password = generatePassword($pwlen);
    system("zip -q -r -P \"$password\" \"$tempdir/$filename\" \"$filename_nosuffix\"");
    errorchk($?, "Creating zip file failed!");

  # create zip file without password
  } else {
    system("zip -q -r \"$tempdir/$filename\" \"$filename_nosuffix\"");
    errorchk($?, "Creating zip file failed!");
  }
  $filesize = (stat("$tempdir/$filename"))[7];
  $req = POST("$URL", [ 'redirect' => '1', 'file' => [ "$tempdir/$filename" ] ], 'content_type' => 'multipart/form-data');


# neither compression nor password protection
} else {
  $filename = "$name$suffix";
  $filesize = (stat("$path$filename"))[7];
  $req = POST("$URL", [ 'redirect' => '1', 'file' => [ "$path$filename" ] ], 'content_type' => 'multipart/form-data');
}


# create progressbar dialog
my $dbusRef=`kdialog --title \"$windowtitle\" --progressbar "Uploading $filename ..." 100`;
if ( $dbusRef =~ /(org\.kde\.kdialog-[0-9]+) \/ProgressDialog/ ) {
  $dbusRef = "$1";
} else {
  errorchk(1, "ERROR: Getting dbus reference failed!");
}
system("qdbus $dbusRef /ProgressDialog showCancelButton true");


# update progress bar
my $gen = $req->content;
if (ref($gen) ne 'CODE') {
  errorchk(1, "ERROR: Uploading file in chunks!");
}
my $total;
my $percent;

$req->content(
  sub {
    my $chunk = &$gen();
    $total += length($chunk) if defined $chunk;
    $percent = floor($total/$filesize*100);
    if ( `qdbus $dbusRef /ProgressDialog wasCancelled` eq "true\n" ) {
      system("qdbus $dbusRef /ProgressDialog close");
      errorchk(1, "ERROR: Upload cancelled!");
    }
    system("qdbus $dbusRef /ProgressDialog Set \"\" value $percent");
    return $chunk;
  }
);


# upload file to filefactory
$response = $ua->request($req);
system("qdbus $dbusRef /ProgressDialog close");
if ( !$response->is_success ) {
  errorchk(1, "$response->status_line");
}
#print $response->content;


# get url for uploaded file
if ( $response->content =~ /(http:\/\/www\.filefactory\.com\/file\/[a-z0-9]+\/n\/[A-Za-z0-9_]+)/ ) {
  if ($file_password == 0) {
    system("kdialog --title \"$windowtitle\" --msgbox \"\nFile upload successful!\nURL: $1\nPassword: $password\n\"");
  } else {
    system("kdialog --title \"$windowtitle\" --msgbox \"\nFile upload successful!\nURL: $1\\n\"");
  }
} else {
  errorchk(1, "Getting URL for uploaded file failed");
}
#print $response->content;


exit(0);


sub generatePassword {
  my $length = shift;
  my $possible = 'abcdefghijklmnopqrstuvwxyz1234567780ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  while ( length($password) < $length ) {
    $password .= substr( $possible, ( int( rand( length($possible) ) ) ), 1 );
  }
  return $password;
}

