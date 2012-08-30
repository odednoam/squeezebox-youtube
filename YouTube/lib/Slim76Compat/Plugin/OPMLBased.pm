package Slim76Compat::Plugin::OPMLBased;

# Allow Plugins to use 7.6 Onebrowser XMLBrowser interface

use strict;
use base 'Slim::Plugin::OPMLBased';

use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use Slim76Compat::Control::XMLBrowser;
use Slim76Compat::Buttons::XMLBrowser;

if ( main::WEBUI ) {
 	require Slim76Compat::Web::XMLBrowser;
}

my $prefs = preferences('server');

my %cli_next = ();

my $init;

# ensure our button mode is initialised
sub initPlugin {
	my $class = shift;

	if (!$init) {
		Slim76Compat::Buttons::XMLBrowser::init();
	}
	
	$class->SUPER::initPlugin(@_);
}

# this is a direct copy with the alternative Slim::Control::XMLBrowser called
sub initCLI {
	my ( $class, %args ) = @_;
	
	my $cliQuery = sub {
	 	my $request = shift;
		Slim76Compat::Control::XMLBrowser::cliQuery( $args{tag}, $class->feed( $request->client ), $request );
	};
	
	# CLI support
	Slim::Control::Request::addDispatch(
		[ $args{tag}, 'items', '_index', '_quantity' ],
	    [ 1, 1, 1, $cliQuery ]
	);
	
	Slim::Control::Request::addDispatch(
		[ $args{tag}, 'playlist', '_method' ],
		[ 1, 1, 1, $cliQuery ]
	);

	$cli_next{ $class } ||= {};

	$cli_next{ $class }->{ $args{menu} } = Slim::Control::Request::addDispatch(
		[ $args{menu}, '_index', '_quantity' ],
		[ 0, 1, 1, $class->cliRadiosQuery( \%args, $args{menu} ) ]
	) if $args{menu};
}

# this is a direct copy but pushes into mode xmlbrowser76compat
sub setMode {
	my ( $class, $client, $method ) = @_;

	if ($method eq 'pop') {

		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $name = $class->getDisplayName();
	
	my $type = $class->type;
	
	my $title = (uc($name) eq $name) ? $client->string( $name ) : $name;
	
	if ( $type eq 'link' ) {
		my %params = (
			header   => $name,
			modeName => $name,
			url      => $class->feed( $client ),
			title    => $title,
			timeout  => 35,
		);

		Slim::Buttons::Common::pushMode( $client, 'xmlbrowser76compat', \%params );
		
		# we'll handle the push in a callback
		$client->modeParam( handledTransition => 1 );
	}
	elsif ( $type eq 'search' ) {
		my %params = (
			header          => $title,
			cursorPos       => 0,
			charsRef        => 'UPPER',
			numberLetterRef => 'UPPER',
			callback        => \&Slim::Buttons::XMLBrowser::handleSearch,
			item            => {
				url     => $class->feed( $client ),
				timeout => 35,
			},
		);
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Text', \%params );
	}
}

# this is a direct copy and is only need as $cli_next is local to the package and we can't access the one in Slim::Plugin::OPMLBase
sub cliRadiosQuery {
	my ( $class, $args, $cli_menu ) = @_;
	my $tag  = $args->{tag};

	my $icon   = $class->_pluginDataFor('icon') ? $class->_pluginDataFor('icon') : 'html/images/radio.png';
	my $weight = $class->weight;

	return sub {
		my $request = shift;

		my $menu = $request->getParam('menu');

		$request->addParam('sort','weight');

		my $name  = $args->{display_name} || $class->getDisplayName();
		my $title = (uc($name) eq $name) ? $request->string( $name ) : $name;

		my $data;
		# what we want the query to report about ourself
		if (defined $menu) {
			my $type = $class->type;
			
			if ( $type eq 'link' ) {
				$data = {
					text         => $title,
					weight       => $weight,
					'icon-id'    => $icon,
					actions      => {
							go => {
								cmd => [ $tag, 'items' ],
								params => {
									menu => $tag,
								},
							},
					},
					window        => {
						titleStyle => 'album',
					},
				};
			}
			elsif ( $type eq 'search' ) {
				$data = {
					text         => $title,
					weight       => $weight,
					'icon-id'    => $icon,
					actions      => {
						go => {
							cmd    => [ $tag, 'items' ],
							params => {
								menu    => $tag,
								search  => '__TAGGEDINPUT__',
							},
						},
					},
					input        => {
						len  => 3,
						help => {
							text => $request->string('JIVE_SEARCHFOR_HELP')
						},
						softbutton1 => $request->string('INSERT'),
						softbutton2 => $request->string('DELETE'),
					},
					window        => {
						titleStyle => 'album',
					},
				};
			}
			
			if ( main::SLIM_SERVICE ) {
				# Bug 7110, icons are full URLs so we must use icon not icon-id
				$data->{icon} = delete $data->{'icon-id'};
			}
		}
		else {
			my $type = $class->type;
			if ( $type eq 'link' ) {
				$type = 'xmlbrowser';
			}
			elsif ( $type eq 'search' ) {
				$type = 'xmlbrowser_search';
			}
			
			$data = {
				cmd    => $tag,
				name   => $title,
				type   => $type,
				icon   => $icon,
				weight => $weight,
			};
		}
		
		# Exclude disabled plugins
		my $disabled = $prefs->get('sn_disabled_plugins');
		
		if ( main::SLIM_SERVICE ) {
			my $client = $request->client();
			if ( $client && $client->playerData ) {
				$disabled  = [ keys %{ $client->playerData->userid->allowedServices->{disabled} } ];
			
				# Hide plugins if necessary (private, beta, etc)
				if ( !$client->canSeePlugin($tag) ) {
					$data = {};
				}
			}
		}
		
		if ( $disabled ) {
			for my $plugin ( @{$disabled} ) {
				if ( $class =~ /^Slim::Plugin::${plugin}::/ ) {
					$data = {};
					last;
				}
			}
		}
		
		# Filter out items which don't match condition
		if ( $class->can('condition') && $request->client ) {
			if ( !$class->condition( $request->client ) ) {
				$data = {};
			}
		}
		
		# let our super duper function do all the hard work
		Slim::Control::Queries::dynamicAutoQuery( $request, $cli_menu, $cli_next{ $class }->{ $cli_menu }, $data );
	};
}

# this is a copy with the alternative Slim::Web::XMLBrowser called
sub webPages {
	my $class = shift;
	
	# Only setup webpages here if a menu is defined by the plugin
	return unless $class->menu;

	my $title = $class->getDisplayName();
	my $url   = 'plugins/' . $class->tag() . '/index.html';
	
	Slim::Web::Pages->addPageLinks( $class->menu(), { $title => $url } );
	
	if ( $class->can('condition') ) {
		Slim::Web::Pages->addPageCondition( $title, sub { $class->condition(shift); } );
	}

	Slim::Web::Pages->addPageFunction( $url, sub {
		my $client = $_[0];
		
		Slim76Compat::Web::XMLBrowser->handleWebIndex( {
			client  => $client,
			feed    => $class->feed( $client ),
			type    => $class->type( $client ),
			title   => $title,
			timeout => 35,
			args    => \@_
		} );
	} );
}

1;
