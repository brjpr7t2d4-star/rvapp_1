// Example usage of RV Owner App
const { RVOwnerApp } = require('./RVOwnerApp');

// Create an instance of RVOwnerApp
const myRVApp = new RVOwnerApp();

console.log('========================================');
console.log('   RV Owner App - User-Generated Content');
console.log('========================================\n');

// Create users
console.log('--- Creating Users ---');
myRVApp.createUser('Alice123');
myRVApp.createUser('Bob456');
myRVApp.createUser('CharlieDev');
myRVApp.createUser('Admin');

// Add admin sample RV locations
console.log('\n--- Adding Sample Locations by Admin ---');
myRVApp.addRVLocation('Times Square RV Park', 'Parking', 40.7128, -74.0060, 'Admin');
myRVApp.addRVLocation('LA Rest Area', 'Rest Area', 34.0522, -118.2437, 'Admin');
myRVApp.addRVLocation('Golden Gate Park', 'Parking', 37.7749, -122.4194, 'Admin');

// Users add new RV-friendly places discovered during travels
console.log('\n--- Users Adding New Locations During Travels ---');
myRVApp.addRVLocation('Yosemite Scenic Viewpoint', 'Sightseeing', 37.8651, -119.5383, 'Alice123');
myRVApp.addRVLocation('Rocky Mountains Campground', 'Camping', 39.7392, -104.9903, 'Bob456');
myRVApp.addRVLocation('Death Valley Rest Stop', 'Rest Area', 36.2325, -116.8292, 'CharlieDev');
myRVApp.addRVLocation('Lake Tahoe RV Resort', 'Camping', 39.0968, -120.0324, 'Alice123');

// Display all RV locations
myRVApp.displayRVLocations();

// Add reviews with photos to RV locations
console.log('--- Adding Reviews to Locations ---');
myRVApp.addReviewToLocation(0, 'Alice123', 'Great place to park! Clean facilities and helpful staff.', 5, 'times_square_1.jpg');
myRVApp.addReviewToLocation(0, 'Bob456', 'Really enjoyed the amenities. Would recommend!', 4, 'times_square_2.jpg');
myRVApp.addReviewToLocation(1, 'Alice123', 'Nice rest area but can be crowded during peak hours.', 3, 'la_rest_1.jpg');
myRVApp.addReviewToLocation(2, 'CharlieDev', 'Excellent location with great views of the bridge.', 5, 'golden_gate_1.jpg');
myRVApp.addReviewToLocation(3, 'Bob456', 'Beautiful views! Worth the drive.', 5, 'yosemite_1.jpg');
myRVApp.addReviewToLocation(4, 'Alice123', 'Scenic and peaceful. Great for families.', 4, 'rocky_mtn_1.jpg');

// Display reviews for specific locations
console.log('\n--- Displaying Reviews ---');
myRVApp.displayReviewsForLocation(0);
myRVApp.displayReviewsForLocation(3);

// Search by type
console.log('--- Searching by Type ---');
myRVApp.findRVLocationsByType('Parking');
myRVApp.findRVLocationsByType('Camping');
myRVApp.findRVLocationsByType('Sightseeing');

// Search by name
console.log('--- Searching by Name ---');
myRVApp.searchLocationsByName('Park');
myRVApp.searchLocationsByName('Mountain');

// Display user statistics
console.log('--- User Statistics ---');
myRVApp.displayUserStatistics('Alice123');
myRVApp.displayUserStatistics('Bob456');
myRVApp.displayUserStatistics('CharlieDev');

// Get locations added by users
console.log('\n--- Locations Added by Each User ---');
const aliceLocations = myRVApp.getLocationsByUser('Alice123');
console.log(`Alice123 added ${aliceLocations.length} location(s):`);
aliceLocations.forEach(loc => console.log(`  - ${loc.name}`));

const bobLocations = myRVApp.getLocationsByUser('Bob456');
console.log(`\nBob456 added ${bobLocations.length} location(s):`);
bobLocations.forEach(loc => console.log(`  - ${loc.name}`));

console.log('\n========================================');
console.log('   End of Demo');
console.log('========================================');
