#!/usr/bin/perl

use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::User; 
use AppCore::Web::Module; # Bootstrap modules and paths so we can 'use' them
use AppCore::Web::Common;
use Boards::Data;
use Boards;
use WriteBlock;

use strict;

# Create an instace of WriteBlock to create new threads
my $controller = WriteBlock->new;

# Find our user
my $user = AppCore::User->retrieve(1);
AppCore::Common->context->user($user);

# Setup blog database connection
our $DbPassword = AppCore::Common->read_file('/tmp/pci_db_password.txt');
{
	$DbPassword =~ s/[\r\n]//g;
}
my $dbh = AppCore::DBI->dbh('jblog','database','root',$DbPassword);


# Extract the story text from the blog posts
my $sth = $dbh->prepare(q{select postid,title,content,postdate from posts where content like '%<div id="story">%' and title like 'Twin Earth Story - Part %'});
$sth->execute;

my @list;
while(my $ref = $sth->fetchrow_hashref)
{
	my $block = $ref->{content};
	my ($story) = $block =~ /<div id=['"]?story['"]?>((?:.|\n)+)<\/div>/;
	my $txt = html2text($story);
	$txt =~ s/\n{3,}/\n\n/;
	push @list, $txt; 
}

#use Data::Dumper;

#print join("\n", @list);

# We have the text - now to create the project and postst

my $board = Boards::Board->find_or_create(
	groupid 	=> $WriteBlock::BOARD_GROUP,
	managerid	=> $user,
	title		=> 'Twin Earth',
	folder_name	=> 'twin_earth',
);

my $block = join "\n", @list;
#print $block;
my @para = split /\n/, $block;
print "BoardID: $board - \"", $board->title, "\"\n";
print "Paragraphs: ", scalar(@para), "\n";

foreach my $para (@para)
{
	my $post = $controller->create_new_thread($board, {
		comment => $para,
		no_html_conversion => 1,
	}, $user);
	
	print "Created PostID $post - \"".$post->subject."\"\n";
}

print "Done\n";
