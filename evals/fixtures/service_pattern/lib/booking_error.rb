class BookingError < StandardError; end
class BookingOverlaps < BookingError; end
class BookingAlreadyCancelled < BookingError; end
class BookingNotConfirmable < BookingError; end
