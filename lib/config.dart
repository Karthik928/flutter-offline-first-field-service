class AppConfig {
  static const String apiBase = String.fromEnvironment('API_BASE_URL');

  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_KEY',
  );

  /// Default network timeout for all API calls
  static const Duration httpTimeout = Duration(seconds: 20);

  // ---------------------------------------------------------------------------
  // 🧩 URI Builders
  // ---------------------------------------------------------------------------

  /// Builds a [Uri] from [path] (relative or absolute) and optional [query].
  ///
  /// - Normalizes redundant slashes
  /// - Merges query params
  /// - Example:
  ///   `AppConfig.uri('/api/users', {'page':'1'})`
  static Uri uri(String path, [Map<String, String>? query]) {
    final isAbs = path.startsWith('http://') || path.startsWith('https://');
    final base = apiBase.endsWith('/')
        ? apiBase.substring(0, apiBase.length - 1)
        : apiBase;

    final joined = isAbs
        ? path
        : '$base${path.startsWith('/') ? path : '/$path'}';

    final u = Uri.parse(joined);
    final mergedQuery = <String, String>{...u.queryParameters, ...?query};
    return mergedQuery.isEmpty ? u : u.replace(queryParameters: mergedQuery);
  }

  /// Short alias for [uri]
  static Uri u(String path, [Map<String, String>? query]) => uri(path, query);

  static String fill(String template, Map<String, String> vars) {
    var s = template;
    vars.forEach((k, v) {
      s = s.replaceAll('{$k}', Uri.encodeComponent(v));
    });
    return s;
  }

  /// Backward-compatible alias for [fill]
  static String p(String template, Map<String, String> vars) =>
      fill(template, vars);

  /// Builds a [Uri] using a templated [path] with vars, e.g.:
  /// ```dart
  /// AppConfig.uriT('/api/employee/{id}', {'id': userId});
  /// ```
  static Uri uriT(
    String template,
    Map<String, String> vars, [
    Map<String, String>? query,
  ]) => uri(fill(template, vars), query);

  // ---------------------------------------------------------------------------
  // 📡 API Endpoint Paths
  // ---------------------------------------------------------------------------

  // 🔐 Authentication
  static const String login = '/api/employee/login';
  static const String logout = '/api/employee/logout';
  static const String employeeById = '/api/employee/{id}';

  // 🕐 Attendance / Duty
  static const String attendance = '/api/attendance';
  static const String attendanceToday = '/api/attendance/today';
  static const String punchInTemplate = '/api/attendance/{id}/punch-in';
  static const String punchOutTemplate = '/api/attendance/{id}/punch-out';
  //static const String sendLocation = '/api/employee/update-location';

  // 🚘 Trips
  static const String trips = '/api/trips';
  static const String tripById = '/api/trips/{id}';
  static const String tripDetailsById = '/api/trips/details/{id}';
  static const String tripEmployeeTemplate = '/api/trips/employee/{id}';

  // 🧾 Dealers / Dealer
  static const String dealers = '/api/dealers';
  static const String dealerByEmployee = '/api/dealers/employee/{id}';
  static const String dealerByID = '/api/dealers/{id}';
  static const String dealerTickets = '/api/dealertickets';

  // 👨‍🌾 Farmers / Farmer
  static const String farmers = '/api/farmers';
  static const String farmersByEmployee = '/api/farmers/employee/{id}';
  static const String farmerByID = '/api/farmers/{id}';
  static const String farmerTicket = '/api/farmertickets';

  // 🧑‍💼 Employee Profile
  static const String employee = '/api/employee/{id}';

  // 🔔 Notifications
  static const String notificationsBase = '/api/notifications';
  static const String scheduleNotification = '/api/notifications/schedule';
  static const String updateNotification = '/api/notifications/{id}';
  static const String notificationsByEmployee =
      '/api/notifications/employee/{id}';

  // Products
  static const String apiProducts = '/api/products';
  static const String apiCategories = '/api/categorys';
  static const String apiSubCategories = '/api/subcategorys/category/{id}';
  static const String apiChildCategories =
      '/api/childcategorys/category/{id}/subcategory/{subid}';
  static const String productsByCategoriesId = '/api/products/category/{id}';
  static const String productsBySubCategoriesId =
      '/api/products/category/{id}/{subid}';
  static const String productsByChildCategoriesId =
      '/api/products/category/{id}/{subid}/{childid}';
  static const String imageBase =
      'https://fieldService-data.s3.ap-south-2.amazonaws.com/uploads/';

  static String imageUrl(String path) {
    if (path.isEmpty) return imageBase;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return '${imageBase.endsWith('/') ? imageBase : '$imageBase/'}$normalizedPath';
  }

  static Uri imageUri(String path) => Uri.parse(imageUrl(path));

  //Expences
  static const String expenseUpload = '/api/expenses/';
  static const String expenseUploadByEmployeeId = '/api/expenses/employee/{id}';

  //Cart
  static const String addToCart = '/api/cart/add';
  static const String getCart = '/api/cart/{employeeid}';
  static const String updateCart = '/api/cart/update';
  static const String deleteCart = '/api/cart/remove';

  //Orders
  static const String createOrder = '/api/order/create';
  static const String ordersById = '/api/order/employee/{employeeid}';
  static const String orderByOrderId = "/api/order/{orderId}";

  //Other
  static const String othervisits = '/api/othervisits/';
  static const String reportsByToken = '/api/dashboard/summeries';
  static const String incentivesById = '/api/employee/incentives/{employeeid}';
  static const String allCompletedTasks = '/api/tasks/my-completed-tasks';
  static const String allPendingTasks = '/api/tasks/my-tasks';
  static const String updatingTasks = '/api/tasks/{task_id}/status';

  //Zonal Manager
  static const String zonalDashboard = '/api/dashboard/zonal';
  static const String zonalEmployees = '/api/zonal-data/employees';
  static const String zonalDealers = '/api/zonal-data/dealers';
  static const String zonalFarmers = '/api/zonal-data/farmers';
  static const String zonalDealersApprove =
      '/api/zonal-data/dealers/{dealer_id}/status';
  static const String zonalFarmersApprove =
      '/api/zonal-data/farmers/{farmer_id}/status';
  static const String zonalDealersandFarmers = '/api/zonal-data/customers';

  //zonal manager tasks
  static const String zonalAllTasks = '/api/tasks';
  static const String zonalEmployeeList = '/api/tasks/employees';
  static const String zonalCreateTasks = '/api/tasks';
  static const String zonalTaskDetails = '/api/tasks/{id}';
  static const String zonalUpdateTasks = '/api/tasks/{id}';
  static const String zonalDeleteTasks = '/api/tasks/{id}';
  static const String zonalStatusTasks = '/api/tasks/{id}/status';

  //zonal manager tickets
  static const String zonalAllTickets = '/api/zonal-data/tickets';
  static const String zonalTicketsByEmployee = '/api/tickets?employeeId={id}';

  //zonal manager visits
  static const String zonalAllVisits = '/api/zonal-data/visits';
  static const String zonalDealerVisits = '/api/visits?type=Dealer';
  static const String zonalFarmerVisits = '/api/visits?type=Farmer';

  //zonal manager orders
  static const String zonalAllOrders = '/api/zonal-data/orders';
  static const String zonalOrdersUpdate = '/api/zonal-data/orders/{orderId}';
  static const String zonalOrdersByEmployee = '/api/orders?employeeId={id}';
}
