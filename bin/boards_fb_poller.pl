#!/usr/bin/perl

use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::User;
use AppCore::Web::Module;
use LWP::Simple qw/get/;
use JSON qw/decode_json/;
use Boards::Data;
use Boards;
use AppCore::Web::Common;
# For making MD5's of FB userids for storage photos
use Digest::MD5 qw/md5_hex/;

use strict;

# Make sure we're only running one polling instance at a time
use Fcntl qw(:flock);
flock(DATA, LOCK_EX|LOCK_NB) or die "Already running";

system("date >> /tmp/boards_fb_poller.crontab");

print date().": $0 Starting...\n";

# Disable spam filtering for this script
$Boards::SPAM_OVERRIDE = 1;

my $controller = Boards->new;

my %seen_feed; # flag feeds we've already synced so we dont duplicate post

# Upload all new posts to FB from Boards
my @posts = Boards::Post->retrieve_from_sql(q{deleted=0 and extra_data like '%"needs_uploaded":1%'});
foreach my $post (@posts)
{
	next if ! $post->boardid->fb_sync_enabled;
	
	my $noun = $post->top_commentid && $post->top_commentid->id ? 'comment' : 'post';
	
	# Upload the post to FB
	$controller->notify_via_facebook('new_'.$noun, $post, { really_upload=>1 });
	
	# Clear the 'needs uploaded' flag
	$post->data->set('needs_uploaded',0);
	$post->data->update;
}

# Now iterate over all boards and attempt to pull down new posts/comments from FB
my @boards = Boards::Board->retrieve_all(enabled => 1);
foreach my $board (@boards)
{
	next if !$board->fb_sync_enabled;
	
	my $fb_feed_id      = $board->fb_feed_id;
	my $fb_access_token = $board->fb_access_token;
	
	if(!$fb_feed_id || !$fb_access_token)
	{
		#print STDERR "Not syncing '".$board->title."' - no FB Feed ID or Access Token.\n";
		next; 
	}
	
	my $feed_url = "https://graph.facebook.com/${fb_feed_id}/feed?access_token=${fb_access_token}";
	
	if($seen_feed{$feed_url})
	{
		#print STDERR "Not syncing '".$board->title."' - already synced feed $fb_feed_id to board '".$seen_feed{$feed_url}->title."'\n";
		next;
	}
	
	$seen_feed{$feed_url} = $board;
	
	update_board($board,$feed_url);
}


print date().": $0 Finished\n\n";


###############################################################################################3


sub update_board
{
	my $board = shift;
	my $feed_url = shift;
	
	my $json = get($feed_url);
	my $feed_hash = decode_json($json);
	my $feed_list = $feed_hash->{data};

	foreach my $fb_post (@$feed_list)
	{
		my $external_id = $fb_post->{id};
		
		my $post = Boards::Post->by_field(external_id => $external_id, deleted => 0);
		
		my $post_is_new = 0;
		if(!$post)
		{
			my $poster_fb_id = $fb_post->{from}->{id};
			my $poster_photo_url = "https://graph.facebook.com/" . $poster_fb_id . "/picture";
			
			# Attempt to locate a local user matching the Facebook user
			my $user = AppCore::User->by_field(fb_userid => $poster_fb_id);
			$user = AppCore::User->by_field(display => $fb_post->{from}->{name}) if !$user;
			$poster_photo_url = download_user_photo($user, $poster_photo_url, $poster_fb_id);
			
			# Create a set of arguments for create_new_thread()
			my $data = {
				poster_name	=> $fb_post->{from}->{name},
				poster_photo	=> $poster_photo_url,
				poster_email	=> $user ? $user->email : undef,
				comment		=> $fb_post->{message} 
			};
			
			# Use Boards to create a new thread
			$post = $controller->create_new_thread($board, $data, $user);
			
			# Apply Facebook-specific data/fields that create_new_thread doesnt know about
			my $create_time = normalize_timestamp($fb_post->{created_time});
			$post->timestamp($create_time);
			
			my $update_time = normalize_timestamp($fb_post->{updated_time} ? $fb_post->{updated_time} : $fb_post->{created_time});
			$post->updated_time($update_time);
			
			# Flag it as from FB and store the FB Post ID for future reference
			$post->external_id($external_id);
			$post->external_source('Facebook');
			#$post->external_url('https://www.facebook.com/pleasanthillchurch'); # TODO
			my ($user,$post_num) = split /_/, $external_id;
			if($user && $post_num)
			{
				$post->external_url('https://www.facebook.com/' . $user . '/posts/' . $post_num);
			}
			$post->update;
			
			$post_is_new = 1;
			
			my $url = $AppCore::Config::WEBSITE_SERVER . "/boards/".$board->folder_name."/".$post->folder_name;
			print "Created post from facebook - # $post - '".$post->subject."' - $url\n";
		}
		
		if($post->external_source eq 'Facebook')
		{
			# Since this post was created FROM facebook (and not by us creating a post then uploading it to FB),
			# we will check the update timestamp and attempt to update our local copy of the message if the
			# facebook post has been recently updated
			my $fb_time = $fb_post->{updated_time};
			$fb_time = $fb_post->{created_time} if !$fb_time;
			$fb_time =~ s/^([^T]+)T([^\+\-]+)/$1 $2/g;
			if(!$post_is_new && ($post->updated_time cmp $fb_time) < 0) # FB is newer...
			{
				# Sync post message 
				my $msg = $fb_post->{message};
				
				# Try to guess if HTML is really just text
				$msg = text2html($msg) if !might_be_html($msg);
				
				if($post->text ne $msg)
				{
					$post->text($msg);
					$post->updated_time($fb_time);
					$post->update;
					
					my $url = $AppCore::Config::WEBSITE_SERVER . "/boards/".$board->folder_name."/".$post->folder_name;
					print "Updated post text from facebook - # $post - '".$post->subject."' - $url\n";
				}
			
			}
		}
		
		# Check for likes on this post
		my $like_hash  = $fb_post->{likes}   || {};
		my $like_count = $like_hash->{count} || 0;
		my $like_list  = $like_hash->{data}  || [];
		if($like_count > 0)
		{
			my @count = Boards::Post::Like->search(postid => $post->id);
			if(@count != $like_count)
			{
				# Do a bit of funny math..
				my $diff = $like_count - @count;
				my @list = @$like_list;
				$diff -= @list;
				
				# Create anonymous likes
				Boards::Post::Like->insert({postid => $post}) for 0 .. $diff - 1;
				print "Post: Created ($diff) anonymous likes on post '".$post->subject."' - existing ".scalar(@count)." likes, ".scalar(@list)." named likes, total likes on FB $like_count\n" if $diff > 0;
				
				#die "terminating test\n";
				# Now create named likes
				foreach my $named_like (@list)
				{
					# Attempt to locate a local user matching the Facebook user
					my $user = AppCore::User->by_field(fb_userid => $named_like->{id});
					$user = AppCore::User->by_field(display => $named_like->{name}) if !$user;
					
					my @result;
					if($user && $user->id)
					{
						# Try to find based on userid
						@result = Boards::Post::Like->search(postid => $post->id, userid => $user->id);
					}
					else
					{
						# Try to find based on just the name of the user
						@result = Boards::Post::Like->search(postid => $post->id, name => $named_like->{name});
					}
					
					# Couldnt find a "like" for this name/user - so create one
					if(!@result)
					{
						my $poster_photo_url = "https://graph.facebook.com/" . $named_like->{id} . "/picture";
						$poster_photo_url = download_user_photo($user, $poster_photo_url, $named_like->{id});
						
						my $ref = Boards::Post::Like->insert({
							postid	=> $post,
							userid	=> $user,
							name	=> $named_like->{name},
							email	=> $user ? $user->email : '',
							photo	=> $poster_photo_url,
						});
						
						my $noun = $post->top_commentid && $post->top_commentid->id ? 'comment' : 'post';
						
						#use Data::Dumper;
						#print STDERR "Debug: ref: $ref, post: $post, Dump:".Dumper($ref).", tmp:".$ref->postid."\n";
						
						$controller->send_notifications('new_like', $ref, {noun=>$noun});
						
						print "Post: Created named like from '$named_like->{name}' (user? $user) on post '".$post->subject."\n";
					}
				}
			}
		}
		
		# Now try to pull down list of comments onto the $post
		
		my $comments_hash = $fb_post->{comments} || {};
		my $cmt_list = $comments_hash->{data} || [];
		foreach my $cmt_ref (@$cmt_list)
		{
			# Note: A Comment posted here THEN uploaded to FB will NEVER appear in the comments list
			# (until the FB api changes) because we upload comments as new top-level stories on FB.
			# So this is only one way - create new comments on our posts based on comments from FB
			my $fb_cmtid = $cmt_ref->{id};
			my $cmt = Boards::Post->by_field(external_id => $fb_cmtid);
			if(!$cmt)
			{
				my $poster_fb_id = $cmt_ref->{from}->{id};
				my $poster_photo_url = "https://graph.facebook.com/" . $poster_fb_id . "/picture";
				
				# Attempt to locate a local user matching the Facebook user
				my $user = AppCore::User->by_field(fb_userid => $poster_fb_id);
				$user = AppCore::User->by_field(display => $cmt_ref->{from}->{name}) if !$user;
				$poster_photo_url = download_user_photo($user, $poster_photo_url, $poster_fb_id);
				
				my $has_top = $post->top_commentid && $post->top_commentid->id;
				my $data = {
					top_commentid		=> $has_top ? $post->top_commentid->id : $post->id,
					parent_commentid	=> $post->id, #$has_top ? 0 : $post->id, ## TODO Will this work or cauase problems to just set it to post->id regardless of $hash_top?
					poster_name		=> $cmt_ref->{from}->{name},
					poster_photo		=> $poster_photo_url,
					comment			=> $cmt_ref->{message},	
				};
				
				# Let Boards do the actual creation for us
				$cmt = $controller->create_new_comment($board,$post,$data,$user);
				
				# Revise the timestamp to match FB timestamp
				my $create_time = normalize_timestamp($cmt_ref->{created_time});
				$cmt->timestamp($create_time);
				
				# Flag it as from FB and store the FB Post ID for future reference
				$cmt->external_id($fb_cmtid);
				$cmt->external_source('Facebook');
				
				my ($user,$post_num,$cmt_num) = split /_/, $fb_cmtid;
				if($user && $post_num && $cmt_num)
				{
					$cmt->external_url('https://www.facebook.com/' . $user . '/posts/' . $post_num);
				}
				$cmt->update;
				
				my $url = $AppCore::Config::WEBSITE_SERVER . "/boards/".$cmt->top_commentid->boardid->folder_name."/".$cmt->top_commentid->folder_name."#c$cmt";
				print "Created comment# $cmt on post# '".$post->subject."' (top post: '".$cmt->top_commentid->subject."') - $url\n";
			}
			
			# Check for likes on this comment
			my $like_count = $cmt_ref->{count} || 0;
			if($like_count > 0)
			{
				my @count = Boards::Post::Like->search(postid => $cmt->id);
				if(@count != $like_count)
				{
					# Do a bit of funny math..
					my $diff = $like_count - @count;
					
					# Create anonymous likes
					Boards::Post::Like->insert({postid => $post}) for 0 .. $diff - 1;
					print "Comment: Created ($diff) anonymous likes on comment '".$cmt->subject."' - existing ".scalar(@count)." likes, total likes on FB $like_count\n" if $diff > 0;
				}
			}
		}
	}
}

sub download_user_photo
{
	my $user = shift;
	my $poster_photo_url = shift;
	my $fb_id = shift;
	
	my $photo = LWP::Simple::get($poster_photo_url);
	my $local_photo_url = "/mods/User/user_photos/". ($user && $user->id ? "user". $user->id : "fb".md5_hex($fb_id)).".jpg";
	my $file_path = $AppCore::Config::APPCORE_ROOT . $local_photo_url;
	if(open(PHOTO, '>' . $file_path))
	{
		print PHOTO $photo;
		close(PHOTO);
		
		if($user && $user->id)
		{
			$user->photo($AppCore::Config::WWW_ROOT . $local_photo_url);
			$user->update;
		}
		
		print "Downloaded user photo to $file_path.\n";
		
		$poster_photo_url = $AppCore::Config::WWW_ROOT . $local_photo_url;
	}
	else
	{
		print STDERR "Error saving photo to $file_path: $!";
		
		if($user && $user->id)
		{
			$user->photo($poster_photo_url);
			$user->update;
		}
	}
	
	return $poster_photo_url;
}

sub normalize_timestamp
{
	my $time = shift;
	$time =~ s/^([^T]+)T([^\+\-]+)/$1 $2/g;
	my ($a,$b,$c,$d,$e,$f) = $time=~/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
	my $dt = DateTime->new(year=>$a,month=>$b,day=>$c,hour=>$d,minute=>$e,second=>$f,time_zone=>'UTC');
	$dt->subtract(hours=>4);
	return $dt->ymd('-').' '.$dt->hms(':');
}

__DATA__
# Data section exists for the purpose of locking

