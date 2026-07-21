// Uniform success envelope returned from every REST endpoint.

class ApiResponse {
  constructor(statusCode, data, message = 'Success') {
    this.statusCode = statusCode;
    this.data = data;
    this.message = message;
    // Anything below 400 is considered a success response.
    this.success = statusCode < 400;
  }
}

export { ApiResponse };
