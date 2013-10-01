{
package AppCore::TimeMark;
	use AppCore::Common;
	use strict;
	use Time::HiRes qw/time/;
	
	sub new 
	{
		my $class = shift;
		my %opts = @_;
		return bless {
			marks	=> [],
			start	=> time()
		}, $class;
	}
	
	sub mark 
	{
		my $self = shift;
		my $text = join '', @_;
		push @{$self->{marks}}, {
			time		=> time(),
			called_from	=> called_from(),
			text		=> $text,
		};
	}
	
	sub print
	{
		my $self = shift;
		my $start_time = $self->{start};
		my $last_time = $start_time;
		my @marks = @{$self->{marks}};
		print STDERR "TimeMark Output:\n";
		foreach my $mark (@marks)
		{
			my $diff = $mark->{time} - $last_time;
			my $total = $mark->{time} - $start_time;
			print STDERR "    ".rpad(sprintf('%.02f',$diff), 8, ' ').' (total time '.rpad(sprintf('%.02f',$total), 8, ' ').') - '.$mark->{text}.' - '.$mark->{called_from}."\n";
			$last_time = $mark->{time};
		}
		print STDERR "\n";
	}
};
1;
