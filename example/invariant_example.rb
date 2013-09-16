# invariant example
#
# assume that there are ActiveRecord classes User that :has_many Addresses

invariant forall{ |address| not address.user.empty? }
invariant "invariant names are useful but optional", forall{ |user| not user.addresses.empty? }
invariant exists(:bob => User, :jake => User) { |bob, jake|
  (bob != jake) && bob.addresses == jake.addresses
}
