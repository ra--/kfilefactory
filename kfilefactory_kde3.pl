#!/usr/bin/perl
# Name:			kfilefactory.pl (kde3 version)
# Purpose:		easily upload a file or directory to filefactory.com
# Version:		0.0.4
# Date:			10.06.2009
# License:		GPLv2
# Author:		Robert Annessi <robert@annessi.at>


use warnings;
use strict;
use LWP::UserAgent;
use File::Temp qw/ tempdir /;
use File::Basename;
use File::stat;
use POSIX qw(floor);
use HTTP::Request::Common qw(POST);


$HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
my $windowtitle = 'Share file';
my $error;


if ( $#ARGV != 0 ) {
	print "Usage: $0 <file|directory>\n";
	exit(0);
}


# ask user to continue
system("kdialog --title \"$windowtitle\" -yesno \"Do you want to upload \"$ARGV[0]\" to filefactory.com?\nIt will be compressed and password protected, but the protection should be considered weak.\"");
if ( $? != 0 ) {
	exit(1);
}


# initiate browser
my $ua = LWP::UserAgent->new;
$ua->agent("");    # do not identify
$ua->requests_redirectable( [ 'GET', 'POST' ] );
$ua->max_redirect(1);

# create temporary directory (will automatically be removed when the script exits)
my $tempdir = tempdir( "kfilefactory.XXXXXXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

# extract filename, path and suffix from argument
( my $name, my $path, my $suffix ) = fileparse( "$ARGV[0]", "\.[^.]*" );
my $namenoslash = "$name";
$namenoslash =~ s/\\//g;
$path =~ s/"//;
$suffix =~ s/"//;

# get start page from filefactory
my $response = $ua->get('http://www.filefactory.com/');
if ( !$response->is_success ) {
	$error = $response->status_line;
	system("kdialog --title \"$windowtitle\" --error \"ERROR: $error\"");
	exit(1);
}
#print $response->content;


# get upload url
if ( $response->content !~ /<form accept-charset="UTF-8" id="uploader" action="(http:\/\/[a-z0-9]+\.filefactory\.com\/upload\.php)" method="post" enctype="multipart\/form-data">/) {
	system("kdialog --title \"$windowtitle\" --error \"ERROR: Parsing website for upload form failed!\"");
	exit(1);
}
my $URL = "$1";
#print $response->content;


# create zip file with random password
my $password = "";
$password = generatePassword(60);
if ( $? != 0 ) {
	system("kdialog --title \"$windowtitle\" --error \"ERROR: Changing directory!\"");
	exit(1);
}
chdir "$path" or die "$!";
system("zip -q -r -P \"$password\" \"$tempdir/$name$suffix.zip\" \"$name$suffix\"");
if ( $? != 0 ) {
	system("kdialog --title \"$windowtitle\" --error \"ERROR: Creating zip file failed!\"");
	exit(1);
}
my $filesize = stat("$tempdir/$namenoslash$suffix.zip")->size;
my $req = POST("$URL", [ 'redirect' => '1', 'file' => [ "$tempdir/$namenoslash$suffix.zip" ] ], 'content_type' => 'multipart/form-data');


# create progressbar dialog
my $dcopRef=`kdialog --title \"$windowtitle\" --progressbar "Uploading $name$suffix.zip ..." 100`;
if ( $dcopRef =~ /DCOPRef\((kdialog-[0-9]+),ProgressDialog\)/ ) {
	$dcopRef = "$1";
} else {
	system("kdialog --title \"$windowtitle\" --error \"ERROR: Getting dcop reference failed!\"");
	exit(1);
}
system("dcop $dcopRef ProgressDialog showCancelButton true");


# update progress bar
my $gen = $req->content;
if (ref($gen) ne 'CODE') {
	system("kdialog --title \"$windowtitle\" --error \"ERROR: Uploading file in chunks!\"");
	exit(1);
}
my $total;
my $percent;

$req->content(
	sub {
		my $chunk = &$gen();
		$total += length($chunk) if defined $chunk;
		$percent = floor($total/$filesize*100);
		if ( `dcop $dcopRef ProgressDialog wasCancelled` eq "true\n" ) {
			system("dcop $dcopRef ProgressDialog close");
			system("kdialog --title \"$windowtitle\" --error \"Upload cancelled!\"");
			exit(1);
		}
		system("dcop $dcopRef ProgressDialog setProgress $percent");
		return $chunk;
	}
);


# upload file to filefactory
$response = $ua->request($req);
system("dcop $dcopRef ProgressDialog close");
if ( !$response->is_success ) {
	$error = $response->status_line;
	system("kdialog --title \"$windowtitle\" --error \"ERROR: $error\"");
	exit(1);
}
#print $response->content;


# get url for uploaded file
if ( $response->content =~ /(http:\/\/www\.filefactory\.com\/file\/[a-z0-9]+\/n\/[A-Za-z0-9_]+)/ ) {
	system("kdialog --title \"$windowtitle\" --msgbox \"File upload successful!\n
	URL: $1\n
	Password: $password\"");
} else {
	system("kdialog --title \"$windowtitle\" --error \"ERROR: Getting URL for uploaded file failed!\"");
	exit(1);
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

