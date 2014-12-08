#!/usr/bin/perl
use strict;

use lib '../lib';
use lib 'lib';

use AppCore::Common;
use AppCore::Web::ReportViewer;
use File::Slurp;


sub usage
{
return qq{
Usage: $0 sql_file [title]\n";

$0 creates a basic report model from the sql file given, suitable for use
with AppCore::Web::ReportViewer.

$0 loads the SQL, parses for parameters (strings like: "foobar = ?"),
and attempts to run the SQL to extract a list of columns from the results.

$0 then prints a nice and tidy perl hash to stdout, immediately suitable
for use with ReportViewer.
	
};


my $sql_file    = shift || die usage();
my $title_guess = shift;
if(!$title_guess)
{
	$title_guess = $sql_file;
	$title_guess =~ s/\..+$//g;
	$title_guess = guess_title($title_guess);
}

my $sql = read_file($sql_file) || die "Cannot read '$sql_file': $!";
	
my @sql_lines = split /\n/, $sql;
my $sql_string = join "\n", map { "\t\t".$_ } @sql_lines;

my $model = {
	sql => $sql_string,
	
};

my (@raw_args) = $sql =~ /([\w\d]+)\s*=\s*\?/g;

my @args = map {{
	value	=> 1, # TODO: What default value should be used here?
	field	=> $_,
	title	=> guess_title($_),
	
	# Hack for stringification below
	value_string => $_ eq 'officeid' ? '$class->stash->{office}' : 1,
	
	# Hack for stringification below
	hidden	=> $_ eq 'officeid' ? 1 : 0,
	
}} @raw_args;

$model->{args} = \@args;

my $view = AppCore::Web::ReportViewer->new();

$view->set_report_model($model);

my $raw_data = $view->generate_report(undef, 1); # 1 = ignore incomplete

#print Dumper $model, $raw_data;

$model->{columns} = $raw_data->{columns};


my @arg_lines = map{qq|
		{
			field	=> '$_->{field}',
			title	=> '$_->{title}',
			
			# If you leave this blank, the user will have to choose a value before seeing the report.
			# If you set a default value here, the report will automatically run as soon as loaded, 
			# and the user can change the value at runtime.
			value	=> $_->{value_string},
			
			# If hidden is a true value, it will never be shown to the user - just passed to the SQL
			hidden	=> $_->{hidden},
			
			# Specify an AppCore::DBI-subclass here if the field is a FK to another table
			# linked	=> '',
			
			# Not required, but you can use this to adjust the type of UI shown to the user
			# type 		=> '',
		}|}
	@args;
		
my $args_formatted = join ",\n", @arg_lines;


my @col_lines = map{qq|	#
	#	{
	#		field	=> '$_->{field}',
	#		title	=> '$_->{title}',
	#	}|}
	@{$model->{columns} || []};
	
my $columns_formatted = join ",\n", @col_lines;
	
my $date = scalar(date());

print qq|
use strict;
return
{
	# This report model was originally generated from the file '$sql_file' on $date
	
	# Title of the report - displayed to the user
	title	=> '$title_guess',
	
	# The SQL used to generate the report.
	sql	=> q{
$sql_string
	},
	
	# Args are the report parameters displayed to the user - args with a true value for 
	# 'hidden' will, of course, be hidden, but still be passed to the SQL.
	args	=> [
$args_formatted,
	],
	
	# Columns can be specified explicitly, 
	# and if not specified, they will be automagically determined from the SQL.
	# Columns are commented out by default because the automagic column code
	# usually does a good job and it automatically will update the columns
	# when if you change the SQL. If you set columns explicitly, the automagic
	# code just uses what you specify here to display the data, regardless of the SQL.
	#
	# columns	=> [
$columns_formatted,
	# ],
	
	# row_mudge_hook() will be called once per row for every row of data from the report.
	# The hashref given is the current row, and any changes made to the values in the
	# hashref will be displayed to the user - you can use HTML, for example, to add
	# links to values. New hash keys will not be displayed as new columns (e.g.
	# you can add new keys, but they wont be displayed anywhere.)
	row_mudge_hook => sub {
		my (\$row) = \@_;
		
		# ...
	},

}
|;
