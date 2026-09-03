import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({required this.shopName, super.key});

  final String shopName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildSummaryCard()),
          SliverToBoxAdapter(child: _buildCategoryGrid()),
          SliverToBoxAdapter(child: _buildSupplierReturns()),
          SliverToBoxAdapter(child: _buildReceiveStockButton()),
          SliverToBoxAdapter(child: _buildActionGrid()),
          SliverToBoxAdapter(child: _buildExpiringSoon()),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          const Icon(Icons.menu, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shopName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Row(
                  children: [
                    Icon(Icons.store_outlined, size: 14, color: Colors.black54),
                    SizedBox(width: 2),
                    Text('Current shop', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ],
            ),
          ),
          Stack(
            children: [
              const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.notifications_none, size: 28),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: const Text(
                    '8',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFFE8F5E9),
            child: Icon(Icons.person, color: Color(0xFF167D68)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '12',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF167D68),
                    height: 1.0,
                  ),
                ),
                SizedBox(height: 4),
                Text('items need attention', style: TextStyle(fontSize: 14, color: Colors.black87)),
              ],
            ),
          ),
          Container(width: 1, height: 60, color: Colors.grey.shade200),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Value at risk', style: TextStyle(fontSize: 12, color: Colors.black54)),
                SizedBox(height: 4),
                Text(
                  'QAR 1,246.50',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.shopping_bag_outlined, color: Color(0xFF167D68), size: 40),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildCategoryCard(
          'Expired',
          '4',
          const Color(0xFFFFF0F0),
          Colors.red,
          Icons.warning_amber_rounded,
        ),
        _buildCategoryCard(
          'Expiring Today',
          '2',
          const Color(0xFFFFF5EC),
          Colors.deepOrange,
          Icons.event_available,
        ),
        _buildCategoryCard(
          'Expiring in 3 days',
          '6',
          const Color(0xFFFFFBF0),
          Colors.orange,
          Icons.schedule,
        ),
        _buildCategoryCard(
          'Expiring in 7 days',
          '8',
          const Color(0xFFFFFBF0),
          Colors.orange,
          Icons.schedule,
        ),
      ],
    );
  }

  Widget _buildCategoryCard(
    String title,
    String count,
    Color bgColor,
    Color iconColor,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(color: iconColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(count, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Icon(Icons.chevron_right, color: Colors.black54),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierReturns() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.sync, color: Colors.indigo, size: 28),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Supplier Returns Due',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text('2', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.black54),
        ],
      ),
    );
  }

  Widget _buildReceiveStockButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF167D68),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner),
            SizedBox(width: 8),
            Text('Receive Stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _buildActionItem('Scan & Sell', Icons.qr_code_scanner, const Color(0xFF167D68)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionItem('Inventory', Icons.inventory_2_outlined, Colors.black87),
          ),
          const SizedBox(width: 8),
          Expanded(child: _buildActionItem('Reports', Icons.bar_chart, Colors.black87)),
          const SizedBox(width: 8),
          Expanded(
            child: _buildActionItem('Add Product', Icons.add_circle_outline, Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: color == Colors.black87 ? Colors.black87 : color,
              fontWeight: color == Colors.black87 ? FontWeight.normal : FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildExpiringSoon() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Expiring Soon',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'View all >',
                  style: TextStyle(color: Color(0xFF167D68), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          _buildProductTile(
            'Almarai Fresh Milk 1L',
            '12 Sep 2025',
            '3 days',
            const Color(0xFFFFF5EC),
            Colors.deepOrange,
          ),
          _buildProductTile(
            'Nido Powder Milk 900g',
            '15 Sep 2025',
            '6 days',
            const Color(0xFFFFF5EC),
            Colors.deepOrange,
          ),
          _buildProductTile(
            'Coca Cola 500ml',
            '20 Aug 2025',
            'Expired',
            const Color(0xFFFFF0F0),
            Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildProductTile(String name, String date, String tag, Color tagBg, Color tagColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image_outlined, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(date, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(4)),
            child: Text(
              tag,
              style: TextStyle(color: tagColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
