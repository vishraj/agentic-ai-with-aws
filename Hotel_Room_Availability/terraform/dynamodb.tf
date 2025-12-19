resource "aws_dynamodb_table" "hotel_room_availability" {
  name         = "hotelRoomAvailability"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "date"

  attribute {
    name = "date"
    type = "S"
  }
}

resource "aws_dynamodb_table" "hotel_room_booking" {
  name         = "hotelRoomBooking"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "bookingID"

  attribute {
    name = "bookingID"
    type = "S"
  }
}
