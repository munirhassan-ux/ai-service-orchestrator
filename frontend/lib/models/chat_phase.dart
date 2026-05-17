enum ChatPhase {
  greeting,
  intake,
  thinking,
  quoting,
  negotiating,
  equipmentAck,
  bookingConfirmed,
}

ChatPhase parseChatPhase(String? phaseStr) {
  switch (phaseStr) {
    case 'greeting':
      return ChatPhase.greeting;
    case 'intake':
      return ChatPhase.intake;
    case 'thinking':
      return ChatPhase.thinking;
    case 'quoting':
      return ChatPhase.quoting;
    case 'negotiating':
      return ChatPhase.negotiating;
    case 'equipment_ack':
      return ChatPhase.equipmentAck;
    case 'booking_confirmed':
      return ChatPhase.bookingConfirmed;
    default:
      return ChatPhase.greeting;
  }
}
