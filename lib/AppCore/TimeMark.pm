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

{
package AppCore::TimeMark::Looped;
	use AppCore::Common;
	use strict;
	use Time::HiRes qw/time/;
	
	sub new 
	{
		my $class = shift;
		my %opts = @_;
		return bless {
			marks	=> {},
			start   => time(),
			tm      => time(),
			seq     => 0,
		}, $class;
	}
	
	sub mark 
	{
		my $self = shift;
		my $text = join '', @_;
		my $id   = called_from();
		my $seq  = $self->{seq} ++;
		
		my $last_time = $self->{tm};
		my $cur_time  = time();
		my $diff      = $cur_time - $last_time;
		my $total     = $cur_time - $self->{start};
		$self->{tm}   = $cur_time;
		
		$self->{marks}->{$id} ||= {
			seq		=> $seq,
			called_from	=> $id,
			text		=> $text,
			time		=> 0,
			total		=> 0,
		};
		
		my $mark = $self->{marks}->{$id};
		$mark->{time}  += $diff;
		$mark->{total} += $total;
	}
	
	sub print
	{
		my $self = shift;
		#my $start_time = $self->{start};
		#my $last_time = $start_time;
		my @marks = sort { $a->{seq} <=> $b->{seq} } values %{$self->{marks} || {}};
		print STDERR "TimeMark Output:\n";
		foreach my $mark (@marks)
		{
			#my $diff = $mark->{time} - $last_time;
			#my $total = $mark->{time} - $start_time;
			my $diff  = $mark->{time};
			my $total = $mark->{total};
			print STDERR "    ".rpad(sprintf('%.02f',$diff), 8, ' ').' (total time '.rpad(sprintf('%.02f',$total), 8, ' ').') - '.$mark->{text}.' - '.$mark->{called_from}."\n";
			#$last_time = $mark->{time};
		}
		print STDERR "\n";
	}
};
1;
