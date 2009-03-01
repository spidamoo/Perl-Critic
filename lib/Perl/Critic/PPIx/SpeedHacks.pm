##############################################################################
#      $URL: http://perlcritic.tigris.org/svn/perlcritic/trunk/distributions/Perl-Critic/lib/Perl/Critic.pm $
#     $Date: 2009-02-01 18:11:13 -0800 (Sun, 01 Feb 2009) $
#   $Author: clonezone $
# $Revision: 3099 $
##############################################################################

package Perl::Critic::PPIx::SpeedHacks;

use strict;
use warnings;
use Scalar::Util qw(weaken);


#-----------------------------------------------------------------------------

no warnings qw(redefine);     # can't avoid this one, for sure,
no warnings qw(ambiguous);    # but not sure how to avoid this.


#-----------------------------------------------------------------------------
# Our Document is immutable, so the serialized version will always be the
# same.  So here we replace Document::serialize() with a caching one.

use PPI::Document;

my $orig_serialize = *PPI::Document::serialize{CODE};
*{PPI::Document::serialize} = \&caching_serialize;
sub caching_serialize { return $_[0]->{_serlialize} ||= &$orig_serialize(@_); }


#----------------------------------------------------------------------------
# And since our Document is immutable, the content of any given Node is always
# going to be the same as well.  So here we replace Node::content() with a
# caching one.

use PPI::Node;

my $orig_content  = *PPI::Node::content{CODE};
*{PPI::Node::content} = \&caching_content;
sub caching_content { return $_[0]->{_content} ||= &$orig_content(@_); }


#----------------------------------------------------------------------------
# The following is based on the chaching find() method that was created for
# Perl::Critic::Document.  The idea is the same: for any given Node, cache
# references to each descendent, and key them by type.  Subsequent requests
# to find a type will be answered by looking in the cache.

# If we feel good about this idea, we can remove the original code in
# Perl::Critic::Document.  Since a PPI::Document is just another subclass
# of PPI::Node, it will automatically inherit this caching behavior.

my $orig_find  = *PPI::Node::find{CODE};
*{PPI::Node::find} = \&caching_find;

sub caching_find {
    my ($self, $wanted, @more_args) = @_;
    my $type = ref $self;

    # This method can only find elements by their class names.  For
    # other types of searches, delegate to the PPI::Node
    if ( ( ref $wanted ) || !$wanted || $wanted !~ m/ \A PPI:: /xms ) {
        return &$orig_find(@_);
    }

    # Build the class cache if it doesn't exist.  This happens at most
    # once per Perl::Critic::Node instance.  %elements_of will be
    # populated as a side-effect of calling the $finder_sub coderef
    # that is produced by the caching_finder() closure.
    if ( !$self->{_elements_of} ) {

        my $cache = {};
        my $finder_coderef = _caching_finder( $cache );
        &$orig_find( $self, $finder_coderef );
        $self->{_elements_of} = $cache;
    }

    # find() must return false-but-defined on fail
    return $self->{_elements_of}->{$wanted} || q{};
}


#-----------------------------------------------------------------------------

my $orig_find_first  = *PPI::Node::find_first{CODE};
*{PPI::Node::find_first} = \&caching_find_first;

sub caching_find_first {
    my ($self, $wanted, @more_args) = @_;

    # This method can only find elements by their class names.  For
    # other types of searches, delegate to the PPI::Document
    if ( ( ref $wanted ) || !$wanted || $wanted !~ m/ \A PPI:: /xms ) {
        return &$orig_find_first(@_);
    }

    my $result = caching_find(@_);
    return $result ? $result->[0] : $result;
}


#-----------------------------------------------------------------------------

my $orig_find_any  = *PPI::Node::find_any{CODE};
*{PPI::Node::find_any} = \&caching_find_any;

sub caching_find_any {
    my ($self, $wanted, @more_args) = @_;

    # This method can only find elements by their class names.  For
    # other types of searches, delegate to the PPI::Document
    if ( ( ref $wanted ) || !$wanted || $wanted !~ m/ \A PPI:: /xms ) {
        return &$orig_find_any(@_);
    }

    my $result = caching_find(@_);
    return $result ? 1 : $result;
}


#----------------------------------------------------------------------------
# This sub was copied verbatim from Perl::Critic::Document.  TODO: We
# must eliminate one of the copies, else factor it out to separate module.

sub _caching_finder {

    my $cache_ref = shift;  # These vars will persist for the life
    my %isa_cache = ();     # of the code ref that this sub returns


    # Gather up all the PPI elements and sort by @ISA.  Note: if any
    # instances used multiple inheritance, this implementation would
    # lead to multiple copies of $element in the $elements_of lists.
    # However, PPI::* doesn't do multiple inheritance, so we are safe

    return sub {
        my (undef, $element) = @_;
        my $classes = $isa_cache{ref $element};
        if ( !$classes ) {
            $classes = [ ref $element ];
            # Use a C-style loop because we append to the classes array inside
            for ( my $i = 0; $i < @{$classes}; $i++ ) { ## no critic(ProhibitCStyleForLoops)
                no strict 'refs';                       ## no critic(ProhibitNoStrict)
                push @{$classes}, @{"$classes->[$i]::ISA"};
                $cache_ref->{$classes->[$i]} ||= [];
            }
            $isa_cache{$classes->[0]} = $classes;
        }

        for my $class ( @{$classes} ) {
            push @{$cache_ref->{$class}}, $element;
        }

        return 0; # 0 tells find() to keep traversing, but not to store this $element
    };
}


#----------------------------------------------------------------------------
# These also replace commonly used methods on PPI::Element with versions
# that cache the results.  I'm not really sure how much of win these are.
# TODO: Need to weaken these references, or else we get memory leaks.

use PPI::Element;

my $orig_sprev  = *PPI::Element::sprevious_sibling{CODE};
*{PPI::Element::sprevious_sibling} = \&caching_sprev;
sub caching_sprev { return $_[0]->{_sprev} ||= &$orig_sprev; };

my $orig_snext = *PPI::Element::snext_sibling{CODE};
*{PPI::Element::snext_sibling} = \&caching_snext;
sub caching_snext { return $_[0]->{_snext} ||= &$orig_snext; };


#----------------------------------------------------------------------------
# This injects a PPI::Element::isa() function that caches the results.
# So far, I'm not convinced that this is actually any faster than the
# builtin isa().

#sub PPI::Element::isa {
#  return UNIVERSAL::isa(@_) if not ref $_[0];
#  return $_[0]->{_isa}->{$_[1]} if exists $_[0]->{_isa}->{$_[1]};
#  return $_[0]->{_isa}->{$_[1]} = UNIVERSAL::isa(@_);
#}

#----------------------------------------------------------------------------
1;

=pod

This module replaces several methods in the PPI namespace with custom
versions that cache their results to improve performance.  This all
relies on the fact that L<Perl::Critic> treats the Document as
immutable.

This code is highly experimental.  You have been warned.

=cut
