// ─── Models ───────────────────────────────────────────────────────────────────

class CartItem {
  final Product product;
  final int qty;
  const CartItem({required this.product, this.qty = 1});
  CartItem copyWith({int? qty}) =>
      CartItem(product: product, qty: qty ?? this.qty);
}

class Product {
  final String? id;
  final String? categoryId;
  final String? subCategoryId;
  final String? childCategoryId;
  final String? category;

  final String? productName;
  final String? shortDescription;
  final String? longDescription;

  final String? productImage;
  final List<String>? productImages;

  final bool? isActive;
  final double? productPrice;

  final String? unit;
  final int? unitValue;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  final int? v;

  Product({
    this.id,
    this.categoryId,
    this.subCategoryId,
    this.childCategoryId,
    this.category,
    this.productName,
    this.shortDescription,
    this.longDescription,
    this.productImage,
    this.productImages,
    this.isActive,
    this.productPrice,
    this.unit,
    this.unitValue,
    this.createdAt,
    this.updatedAt,
    this.v,
  });

  String? get imagePath {
    if (productImage != null && productImage!.isNotEmpty && productImage != 'null') return productImage;
    if (productImages != null && productImages!.isNotEmpty) return productImages!.first;
    return null;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    double? parsedPrice;
    final v = json['productPrice'] ?? json['price'];
    if (v is num) parsedPrice = v.toDouble();
    if (v is String) parsedPrice = double.tryParse(v);

    // Parse images list
    List<String>? images;
    if (json['productImages'] is List) {
      images = (json['productImages'] as List)
          .whereType<String>()
          .where((e) => e.isNotEmpty && e != 'null')
          .toList();
    }

    // Pick first image
    String? image;
    final rawImage = json['productImage'] ?? json['image'];
    if (rawImage is String && rawImage.isNotEmpty && rawImage != 'null') {
      image = rawImage;
    } else if (images != null && images.isNotEmpty) {
      image = images.first;
    }

    return Product(
      id: json['_id'] as String?,

      categoryId:
          json['categoryId']?.toString() ?? json['category']?.toString(),

      subCategoryId:
          json['subCategoryId']?.toString() ??
          json['subcategoryId']?.toString() ??
          json['subCategory']?.toString(),

      childCategoryId:
          json['childCategoryId']?.toString() ??
          json['childcategoryId']?.toString() ??
          json['childCategory']?.toString(),

      category: json['category'] as String?,

      productName: json['productName'] as String?,
      shortDescription: json['shortDescription'] as String?,
      longDescription: json['longDescription'] as String?,

      productImage: image,
      productImages: images,

      isActive: json['isActive'] as bool?,

      productPrice: parsedPrice,

      unit: json['unit'] as String?,
      unitValue: json['unitValue'] is num
          ? (json['unitValue'] as num).toInt()
          : null,

      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,

      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,

      v: json['__v'] as int?,
    );
  }
}

class ProductCategory {
  final String id;
  final String? name;
  final String? imageUrl;
  final bool? isActive;

  ProductCategory({required this.id, this.name, this.imageUrl, this.isActive});

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    final id = (json['_id'] ?? json['id'] ?? '').toString();
    final name =
        json['categoryName'] ??
        json['subCategoryName'] ??
        json['childCategoryName'] ??
        json['name'];
    final imageUrl =
        json['categoryImage'] ??
        json['subcategoryImage'] ??
        json['childCategoryImage'] ??
        json['image'];

    return ProductCategory(
      id: id,
      name: name?.toString(),
      imageUrl: imageUrl?.toString(),
      isActive: json['isActive'] as bool?,
    );
  }
}