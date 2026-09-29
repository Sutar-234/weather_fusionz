// weather-station/kernel_module/weather_driver.c
// Simple character device driver: /dev/weather

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/device.h>
#include <linux/mutex.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Virtual Weather Station character driver");

#define DEVICE_NAME "weather"
#define CLASS_NAME  "weatherclass"

static int    major_num;
static struct class*  weather_class;
static struct device* weather_device;
static struct cdev    weather_cdev;

static struct {
    int t;
    int h;
    int p;
    int samples;
} g_data = { 22000, 55000, 1013250, 0 };

static DEFINE_MUTEX(g_lock);

static ssize_t weather_read(struct file* f, char __user* buf,
                            size_t len, loff_t* off) {
    char kbuf[128];
    int n;

    mutex_lock(&g_lock);
    n = snprintf(kbuf, sizeof(kbuf),
        "temperature=%d.%03d\n"
        "humidity=%d.%03d\n"
        "pressure=%d.%03d\n"
        "samples=%d\n",
        g_data.t / 1000, g_data.t % 1000,
        g_data.h / 1000, g_data.h % 1000,
        g_data.p / 1000, g_data.p % 1000,
        g_data.samples);
    mutex_unlock(&g_lock);

    return simple_read_from_buffer(buf, len, off, kbuf, n);
}

static ssize_t weather_write(struct file* f, const char __user* buf,
                             size_t len, loff_t* off) {
    char kbuf[128];
    int t, h, p;

    if (len >= sizeof(kbuf)) return -EINVAL;
    if (copy_from_user(kbuf, buf, len)) return -EFAULT;
    kbuf[len] = '\0';

    if (sscanf(kbuf, "%d %d %d", &t, &h, &p) == 3) {
        mutex_lock(&g_lock);
        g_data.t = t;
        g_data.h = h;
        g_data.p = p;
        g_data.samples++;
        mutex_unlock(&g_lock);
        return len;
    }
    return -EINVAL;
}

static const struct file_operations fops = {
    .owner = THIS_MODULE,
    .read  = weather_read,
    .write = weather_write,
};

static int __init ws_init(void) {
    dev_t dev;

    if (alloc_chrdev_region(&dev, 0, 1, DEVICE_NAME) < 0) return -1;
    major_num = MAJOR(dev);

    cdev_init(&weather_cdev, &fops);
    if (cdev_add(&weather_cdev, dev, 1) < 0) {
        unregister_chrdev_region(dev, 1);
        return -1;
    }

    weather_class = class_create(CLASS_NAME);
    if (IS_ERR(weather_class)) {
        cdev_del(&weather_cdev);
        unregister_chrdev_region(dev, 1);
        return PTR_ERR(weather_class);
    }

    weather_device = device_create(weather_class, NULL, dev,
                                   NULL, DEVICE_NAME);
    if (IS_ERR(weather_device)) {
        class_destroy(weather_class);
        cdev_del(&weather_cdev);
        unregister_chrdev_region(dev, 1);
        return PTR_ERR(weather_device);
    }

    pr_info("weather_driver: /dev/%s ready\n", DEVICE_NAME);
    return 0;
}

static void __exit ws_exit(void) {
    device_destroy(weather_class, MKDEV(major_num, 0));
    class_destroy(weather_class);
    cdev_del(&weather_cdev);
    unregister_chrdev_region(MKDEV(major_num, 0), 1);
    pr_info("weather_driver: unloaded\n");
}

module_init(ws_init);
module_exit(ws_exit);
